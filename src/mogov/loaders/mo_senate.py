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
# bounded so a block missing its "Vacancies" line can't swallow the rest of the journal
BLOCK = re.compile(rf"YEAS{DASH}Senators?.{{0,2500}}?Vacancies{DASH}[^\n]*", re.S)
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
# running page headers: "Journal of the Senate 118", "Sixty-Sixth Day—Thursday, April 24, 2025"
PAGE_FURNITURE = re.compile(
    r"^(?:Journal of the Senate \d+|\d+ Journal of the Senate|.*\bDAY\s*[—–-]\s*[A-Z]+DAY,.*)$", re.M | re.I
)
DAY_HEADER = re.compile(r"([A-Z\-]+ DAY)\s*[—–-]\s*[A-Z]+DAY,\s*([A-Z]+ \d{1,2}, \d{4})")


def parse_journal(text: str) -> list[dict]:
    """All recorded votes in a journal's text -> [{context, category, name, declared_count, block_index}]."""
    day = DAY_HEADER.search(text)
    rows = []
    for i, m in enumerate(BLOCK.finditer(text)):
        block = PAGE_FURNITURE.sub("", m.group(0))
        before = text[max(0, m.start() - 600) : m.start()]
        context = re.split(r"(?<=[.:])\s*\n", before.strip())[-1].replace("\n", " ").strip()
        for section in SECTION.finditer(block.replace("\n", " ")):
            category, names = section.group(1), section.group(2)
            if category == "Vacancies":
                continue
            count = re.search(rf"{re.escape(names)}{DASH}(\d+)", block.replace("\n", " "))
            if leading := re.match(r"(\d+)\s+", names):
                count, names = leading, names[leading.end() :]
            for surname, district in NAME.findall(names):
                # "Senato" and the like: the heading word cut off by the PDF text
                if surname in {"None", "Dist"} or (len(surname) >= 5 and "Senators".startswith(surname)):
                    continue
                name = f"{surname} ({district})" if district else surname
                rows.append(
                    {
                        "block_index": i,
                        "journal_day": day.group(1) if day else None,
                        "journal_date": day.group(2) if day else None,
                        "context": context[-400:],
                        "category": category,
                        "name": name,
                        "declared_count": int(count.group(1)) if count else None,
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
