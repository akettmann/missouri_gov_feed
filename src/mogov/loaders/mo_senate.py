"""Missouri Senate journals: the only per-senator roll-call record.

Daily journal PDFs are listed at senate.mo.gov/journallist/?SelectedYear=YYYY. Each recorded vote
reads "YEAS—Senators <names>—N  NAYS—Senators ... Absent—... Absent with leave—... Vacancies—...".
Every block becomes one raw row per (vote, senator token), with the sentence that introduced the
vote ("SB 974 was read the 3rd time and passed by the following vote:") kept as context. Tokens are
surnames, "(16)"-style district suffixes when two senators share one; dbt matches them to people.
"""

import io
import os
import re
from datetime import date

import pdfplumber

from mogov import db
from mogov.http import fetch
from mogov.loaders import loader

BASE = "https://www.senate.mo.gov"
YEARS = [int(y) for y in os.environ.get("MOGOV_SENATE_YEARS", "2023,2024,2025,2026").split(",")]

DASH = "[—–-]"
CATEGORIES = ["YEAS", "NAYS", "Absent with leave", "Absent", "Vacancies"]
# bounded so a block missing its "Vacancies" line can't swallow the rest of the journal
BLOCK = re.compile(rf"YEAS{DASH}Senators?.{{0,2500}}?Vacancies{DASH}[^\n]*", re.S)
SECTION = re.compile(
    rf"(YEAS|NAYS|Absent with leave|Absent|Vacancies){DASH}(?:Senators?{DASH}?)?\s*"
    rf"(.*?)(?={DASH}\d+\b|{DASH}?None\b|$)",
    re.S,
)
# "Brown (16)" (2025+) or "Brown (16th Dist.)" (earlier); normalized to "Brown (16)"
NAME = re.compile(r"([A-Z][A-Za-z'’\-]+)(?: \((\d+)(?:st|nd|rd|th)?(?: ?Dist\.?)?\))?")
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
            for surname, district in NAME.findall(names):
                if surname in {"Senator", "Senators", "None", "Dist"}:
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
    html = fetch(f"{BASE}/journallist/", {"SelectedYear": year}, max_age=86400 if year >= date.today().year else None)
    links = re.findall(rb'href="(/\d{2}info/Journals/[^"]+\.pdf)"', html, flags=re.I)
    return sorted({BASE + link.decode() for link in links})


@loader("mo_senate")
def load() -> dict[str, int]:
    votes, journals = [], []
    for year in YEARS:
        for url in _journal_urls(year):
            try:
                data = fetch(url, max_age=None, delay=0.5)
            except Exception as exc:
                journals.append((url, {"year": year, "url": url, "error": str(exc)}))
                continue
            with pdfplumber.open(io.BytesIO(data)) as pdf:
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)
            rows = parse_journal(text)
            journals.append((url, {"year": year, "url": url, "n_vote_rows": len(rows)}))
            votes.extend((f"{url}#{j}", {"year": year, "url": url, **r}) for j, r in enumerate(rows))
    return {
        "mo_senate_journals": db.replace_json("mo_senate_journals", journals, source_url=BASE),
        "mo_senate_votes": db.replace_json("mo_senate_votes", votes, source_url=BASE),
    }
