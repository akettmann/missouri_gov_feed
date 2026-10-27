"""Missouri Senate topical index: every bill of a regular session filed under each subject keyword.

senate.mo.gov/BillTracking/bills/keywords?year=YYYY&session=R is one page per session (3-6 MB) with a card
per (keyword, bill): Senate bills and resolutions, plus the House bills that reached the Senate. The keywords
are the legislature's shared subject index, the same terms as the House bill XML's subjects (which only
starts in 2024), so this fills in subjects for earlier sessions and for Senate bills. Extraordinary sessions
have no index (the page comes back empty). Each card lands as-is: keyword, bill label, link, description,
sponsors.
"""

from datetime import date

from lxml import etree, html

from mogov import db, obs
from mogov.config import window_years
from mogov.http import fetch
from mogov.loaders import loader
from mogov.loaders.mo_senate_bills import senate_interval

log = obs.get_logger(__name__)

BASE = "https://www.senate.mo.gov"
TABLE = "mo_senate_bill_topics"


def _has_class(name: str) -> str:
    """XPath test for one whole token of the class attribute (so "card" does not match "card__header")."""
    return f"contains(concat(' ', normalize-space(@class), ' '), ' {name} ')"


# a keyword heading or a bill link, in document order: the headings partition the bill cards into sections
MARKS = etree.XPath(f"//span[{_has_class('heading--label')}] | //a[{_has_class('bill-number-color')}]")
CARD_OF = etree.XPath(f"ancestor::div[{_has_class('card')}][1]")
PARAGRAPHS = etree.XPath(".//p")
SPONSORS = etree.XPath(f".//a[{_has_class('sponsor-item')}]")


def _text(el: html.HtmlElement) -> str:
    return " ".join(el.text_content().split())


def parse_index(page: str) -> list[dict]:
    """A topical index page -> [{keyword, bill_label, bill_url, description, sponsors: [{name, url}]}]."""
    rows = []
    keyword = None
    for el in MARKS(html.document_fromstring(page)):
        if el.tag == "span":
            keyword = _text(el)
            continue
        if keyword is None:  # a bill link above the first heading belongs to no keyword
            continue
        cards = CARD_OF(el)
        card = cards[0] if cards else el
        paragraphs = PARAGRAPHS(card)
        rows.append(
            {
                "keyword": keyword,
                "bill_label": _text(el),
                "bill_url": el.get("href"),
                "description": _text(paragraphs[0]) if paragraphs else "",
                "sponsors": [
                    {"name": _text(a).removeprefix("Sponsor:").strip(), "url": a.get("href")} for a in SPONSORS(card)
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
            page = fetch(url, {"year": year, "session": "R"}, max_age=max_age, min_interval=senate_interval()).decode(
                "utf-8", "replace"
            )
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
