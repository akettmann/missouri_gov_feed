"""Missouri Senate journals: the only per-senator roll-call record.

Daily journal PDFs are listed at senate.mo.gov/journallist/?SelectedYear=YYYY. Each recorded vote
reads "YEAS—Senators <names>—N  NAYS—Senators ... Absent—... Absent with leave—... [Excused from voting—...]
Vacancies—...".
Every block becomes one raw row per (vote, senator token), with the sentence that introduced the
vote ("SB 974 was read the 3rd time and passed by the following vote:") kept as context. Tokens are
surnames, "(16)"-style district suffixes when two senators share one; dbt matches them to people.
"""

import re
from datetime import date

from mogov import db, obs, pdftext
from mogov.config import window_years
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://www.senate.mo.gov"

DASH = "[—–-]"
CATEGORIES = ["YEAS", "NAYS", "Absent with leave", "Absent", "Excused from voting", "Vacancies"]
CATEGORY = "|".join(CATEGORIES)
# bounded so a block missing its "Vacancies" line can't swallow the rest of the journal. From 2024 the journal prints
# "Excused from voting—Senator X—1" AFTER the Vacancies line (a page break can fall between the two, leaving running
# page-header lines in between), so a trailing one is kept.
# running page headers: "Journal of the Senate 118", "623 Forty-Fourth Day - Thursday, April 4, 2024"
_PAGE_ALTERNATIVES = r"Journal of the Senate \d+|\d+ Journal of the Senate|[^\n]*\bDAY\s*[—–-]\s*[A-Z]+DAY,[^\n]*"
_PAGE_LINE = rf"(?i:{_PAGE_ALTERNATIVES})[ \t]*\n"
BLOCK = re.compile(
    rf"YEAS{DASH}Senators?.{{0,2500}}?Vacancies{DASH}[^\n]*(?:\n(?:{_PAGE_LINE})*Excused from voting{DASH}[^\n]*)?",
    re.S,
)
# A section's names end at its "—N" total, "None", or the next section. Some journals print the total
# before the names ("Absent with leave—Senators—2 Eigel Gannon"); that leading number is the total.
SECTION = re.compile(
    rf"({CATEGORY}){DASH}(?:Senators?{DASH}?)?\s*"
    rf"(.*?)(?={DASH}\d+\b|{DASH}?None\b|\s(?:{CATEGORY}){DASH}|$)",
    re.S,
)
# Surnames of two words, which a space-separated list can't tell apart from two senators.
COMPOUND_SURNAMES = ["Thompson Rehder"]
# "Brown (16)" (2025+) or "Brown (16th Dist.)" (earlier); normalized to "Brown (16)"
NAME = re.compile(rf"({'|'.join(COMPOUND_SURNAMES)}|[A-Z][A-Za-z'’\-]+)(?: \((\d+)(?:st|nd|rd|th)?(?: ?Dist\.?)?\))?")
# Two surnames with the space lost: a capitalized word of 3+ letters running into another ("SaterSchatz"), but not
# "Mac"/"Mc" names (McCreery has one lowercase letter before the second capital; MacDonald is excluded by name).
RUN_TOGETHER = re.compile(r"\b(?!Mac)([A-Z][a-z]{2,})([A-Z][a-z]{2,})\b")
PAGE_FURNITURE = re.compile(rf"^(?:{_PAGE_ALTERNATIVES})$", re.M | re.I)
DAY_HEADER = re.compile(r"([A-Z\-]+ DAY)\s*[—–-]\s*[A-Z]+DAY,\s*([A-Z]+ \d{1,2}, \d{4})")
# veto session journals have no "...DAY—": "VETO SESSION" then "WEDNESDAY, SEPTEMBER 15, 2021"
DATE_LINE = re.compile(r"^[A-Z]+DAY,\s*([A-Z]+ \d{1,2}, \d{4})$", re.M)


def _journal_day(text: str) -> tuple[str | None, str | None]:
    """(day name, date) from the journal's first header, e.g. ("FIFTH DAY", "JANUARY 15, 2025")."""
    if day := DAY_HEADER.search(text):
        return day.group(1), day.group(2)
    if date_line := DATE_LINE.search(text[:2000]):
        return ("VETO SESSION" if "VETO SESSION" in text[: date_line.start()] else None), date_line.group(1)
    return None, None


def _vacancies(block: str) -> int | None:
    """The block's closing "Vacancies—None" / "Vacancies—1" / "Vacancies—Senator—1" as a count."""
    m = re.search(rf"Vacancies{DASH}([^\n]*)", block)
    if not m:
        return None
    # only the first token counts: "None", or "N" / "Senator—N", never a digit further along the line
    rest = m.group(1).strip()
    if re.match(r"None\b", rest, re.I):
        return 0
    if number := re.match(rf"(?:Senators?{DASH}?)?\s*(\d+)", rest):
        return int(number.group(1))
    return None


def parse_journal(text: str) -> list[dict]:
    """All recorded votes in a journal's text -> [{context, category, name, declared_count, vacancies, block_index}]."""
    journal_day, journal_date = _journal_day(text)
    rows = []
    for i, m in enumerate(BLOCK.finditer(text)):
        block = PAGE_FURNITURE.sub("", m.group(0))
        vacancies = _vacancies(block)
        before = text[max(0, m.start() - 600) : m.start()]
        context = re.split(r"(?<=[.:])\s*\n", before.strip())[-1].replace("\n", " ").strip()
        for section in SECTION.finditer(block.replace("\n", " ")):
            category, names = section.group(1), section.group(2)
            if category == "Vacancies":
                continue
            count = re.search(rf"{re.escape(names)}{DASH}(\d+)", block.replace("\n", " "))
            if leading := re.match(r"(\d+)\s+", names):
                count, names = leading, names[leading.end() :]
            # the PDF text sometimes drops the space between two names ("SaterSchatz")
            names = RUN_TOGETHER.sub(r"\1 \2", names)
            for surname, district in NAME.findall(names):
                # "Senato" and the like: the heading word cut off by the PDF text
                if surname in {"None", "Dist"} or (len(surname) >= 5 and "Senators".startswith(surname)):
                    continue
                name = f"{surname} ({district})" if district else surname
                rows.append(
                    {
                        "block_index": i,
                        "journal_day": journal_day,
                        "journal_date": journal_date,
                        "context": context[-400:],
                        "category": category,
                        "name": name,
                        "declared_count": int(count.group(1)) if count else None,
                        "vacancies": vacancies,
                    }
                )
    return rows


def _journal_urls(year: int) -> list[str]:
    # past years monthly, not never: a listing cached mid-session would otherwise miss that session's later journals
    max_age = 86400 if year >= date.today().year else 30 * 86400
    html = fetch(f"{BASE}/journallist/", {"SelectedYear": year}, max_age=max_age)
    links = re.findall(rb'href="(/\d{2}info/Journals/[^"]+\.pdf)"', html, flags=re.I)
    return sorted({BASE + link.decode() for link in links})


@loader("mo_senate", service="www.senate.mo.gov", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: journal PDFs (by URL)."""
    journals = shard.take(((url, year) for year in window_years() for url in _journal_urls(year)), key=lambda j: j[0])
    with db.JsonSink(shard, source_url=BASE, tables=["mo_senate_journals", "mo_senate_votes"]) as sink:
        progress = obs.Progress("journal PDFs", len(journals), log)
        for url, year in journals:
            progress.tick()
            try:
                data = fetch(url, max_age=None, delay=0.5)
            except Exception as exc:
                sink.add("mo_senate_journals", url, {"year": year, "url": url, "error": str(exc)})
                continue
            text = "\n".join(pdftext.page_texts(data))
            rows = parse_journal(text)
            sink.add("mo_senate_journals", url, {"year": year, "url": url, "n_vote_rows": len(rows)})
            sink.extend(
                "mo_senate_votes", ((f"{url}#{j}", {"year": year, "url": url, **r}) for j, r in enumerate(rows))
            )
        progress.finish()
    return sink.counts
