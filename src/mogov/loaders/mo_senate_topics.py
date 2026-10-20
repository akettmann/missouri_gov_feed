"""Missouri Senate topical index: every bill of a regular session filed under each subject keyword.

senate.mo.gov/BillTracking/bills/keywords?year=YYYY&session=R is one page per session (3-6 MB) with a card
per (keyword, bill): Senate bills and resolutions, plus the House bills that reached the Senate. The keywords
are the legislature's shared subject index, the same terms as the House bill XML's subjects (which only
starts in 2024), so this fills in subjects for earlier sessions and for Senate bills. Extraordinary sessions
have no index (the page comes back empty). Each card lands as-is: keyword, bill label, link, description,
sponsors.
"""

import html
import re
from datetime import date

from mogov import db, obs
from mogov.config import window_years
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://www.senate.mo.gov"
TABLE = "mo_senate_bill_topics"

KEYWORD = re.compile(r'<span class="heading--label">(.*?)</span>', re.S)
CARD = re.compile(
    r'<a href="([^"]+)" class="bill-number-color">\s*(.*?)\s*</a>.*?<p[^>]*>(.*?)</p>(.*?)(?=<div class="card card|$)',
    re.S,
)
SPONSOR = re.compile(r'<a href="([^"]+)" class="sponsor-item"[^>]*>\s*(.*?)\s*</a>', re.S)


def _text(fragment: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", fragment))).strip()


def parse_index(page: str) -> list[dict]:
    """A topical index page -> [{keyword, bill_label, bill_url, description, sponsors: [{name, url}]}]."""
    rows = []
    marks = list(KEYWORD.finditer(page))
    for i, m in enumerate(marks):
        section = page[m.end() : marks[i + 1].start() if i + 1 < len(marks) else len(page)]
        for url, label, description, rest in CARD.findall(section):
            rows.append(
                {
                    "keyword": _text(m.group(1)),
                    "bill_label": _text(label),
                    "bill_url": html.unescape(url),
                    "description": _text(description),
                    "sponsors": [
                        {"name": _text(name).removeprefix("Sponsor:").strip(), "url": html.unescape(href)}
                        for href, name in SPONSOR.findall(rest)
                    ],
                }
            )
    return rows


@loader("mo_senate_topics", service="www.senate.mo.gov")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: regular-session years."""
    years = shard.take(window_years())
    with db.JsonSink(shard, source_url=BASE, tables=[TABLE]) as sink:
        progress = obs.Progress("session indexes", len(years), log)
        for year in years:
            url = f"{BASE}/BillTracking/bills/keywords"
            # the open session's index changes daily; a past one only with late corrections
            max_age = 86400 if year >= date.today().year else 30 * 86400
            page = fetch(url, {"year": year, "session": "R"}, max_age=max_age, delay=0.5).decode("utf-8", "replace")
            rows = parse_index(page)
            if not rows:
                log.warning("mo_senate_topics.empty_index", year=year)
            source_url = f"{url}?year={year}&session=R"
            for r in rows:
                key = f"{year}/R/{r['keyword']}/{r['bill_label']}"
                sink.add(TABLE, key, {"year": year, "session_type": "R", **r}, source_url=source_url)
            progress.tick()
        progress.finish()
    return sink.counts
