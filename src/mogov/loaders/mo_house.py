"""Missouri House of Representatives: official XML exports + per-roll-call vote PDFs.

- documents.house.mo.gov/xml/{session}.zip for closed sessions; per-file XML for the open one.
  Members (roster, committees, bio, sponsored bills) and bills (sponsors, actions, roll-call totals).
- Roll-call PDFs (2014+) are the only per-member House vote record. Each is parsed into one raw
  row per (roll call, member token); tokens are surnames like "SMITH 46" or "MR SPEAKER" and are
  matched to members in dbt. The XML links only roll calls on House bills, so each session day's PDFs
  (billsYYS/rollcalls/{day}.{nnn}.pdf) are also probed in order, which finds the House's votes on
  Senate bills and procedural votes.

The site asks that automated clients poll its XML no more than every 30 minutes; caching is a day.
"""

import io
import re
import zipfile
from collections import defaultdict
from collections.abc import Callable, Iterator
from datetime import date
from functools import partial

from lxml import etree

from mogov import db, obs, pdftext, xmljson, xmlparse
from mogov.config import window_years
from mogov.http import CacheMiss, fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://documents.house.mo.gov"
# Session codes: two-digit year + type (1 = regular, 2-4 = extraordinary sessions). Which extraordinary
# sessions exist is discovered: the site answers unknown codes with an HTML page, not a 404.
SESSION_TYPES = "1234"
POLITE_DELAY = 0.3

VOTE_TOKEN = re.compile(r"(?<![A-Z])([YNP@]) +- +([A-Z][A-Z'.\- ]*?[A-Z.](?: \d{1,3})?)(?=\s{2,}|\s+[YNP@] +- |\s*$)")
HEADER_FIELDS = {
    "session_day": re.compile(r"Session Day\s*:\s*(\d+)"),
    "vote_date": re.compile(r"Date\s*:\s*(\d{1,2}/\d{1,2}/\d{4})"),
    "rollcall_number": re.compile(r"Roll Call\s*:\s*(\d+)"),
}
ROLLCALL_URL = re.compile(r"/bills(\d{3})/rollcalls/(\d{3})\.(\d{3})\.pdf$")
# Days probed past the last session day the XML links a roll call for (days with only Senate-bill votes),
# and days probed in a session whose XML links none.
DAY_SLACK = 3
DAYS_IF_UNKNOWN = 10
TABLES = ["mo_house_members", "mo_house_bills", "mo_house_lists", "mo_house_rollcalls", "mo_house_rollcall_votes"]


def _is_xml(data: bytes) -> bool:
    return data.lstrip()[:1] == b"<" and not data.lstrip()[:15].lower().startswith(b"<!doctype html")


def _links(xml: bytes, tag: str) -> list[str]:
    """Texts of every <tag> element in a document (any namespace/attributes); none if it isn't parseable XML."""
    try:
        root = xmlparse.parse(xml)
    except (ValueError, etree.XMLSyntaxError):
        return []
    return [text for _, text in xmlparse.iter_text(root, tag)]


def _session_files(code: str, year: int) -> dict[str, bytes]:
    """All XML files for a House session, keyed by upper-cased file name ({} if the session doesn't exist)."""
    past = year < date.today().year
    data = fetch(f"{BASE}/xml/{code}.zip", max_age=(30 if past else 7) * 86400, delay=POLITE_DELAY)
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            return {
                name.rsplit("/", 1)[-1].upper(): zf.read(name)
                for name in zf.namelist()
                if name.lower().endswith(".xml")
            }
    if past or not code.endswith("1"):
        return {}  # no such session
    # Open regular session: no zip yet, walk the list files.
    files: dict[str, bytes] = {}
    for kind in ("MemberList", "BillList", "SenateActList", "SessionList"):
        try:
            listing = fetch(f"{BASE}/xml/{code}-{kind}.XML", delay=POLITE_DELAY)
        except Exception:
            continue
        if _is_xml(listing):
            files[f"{code}-{kind}.XML".upper()] = listing
    for kind, link_tag in (("MemberList", "RepresentativeXMLLink"), ("BillList", "BillXMLLink")):
        listing = files.get(f"{code}-{kind}.XML".upper())
        if not listing:
            continue
        for url in _links(listing, link_tag):
            files[url.rsplit("/", 1)[-1].upper()] = fetch(url, delay=POLITE_DELAY)
    return files


def _rollcall_url(code: str, day: int, number: int) -> str:
    return f"{BASE}/billtracking/bills{code}/rollcalls/{day:03d}.{number:03d}.pdf"


def _fetch_rollcall(url: str, closed: bool) -> bytes:
    """A roll-call PDF, or the site's HTML error page if there is no such roll call. PDFs never change once
    posted; a miss is re-checked daily while its session can still gain roll calls."""
    try:
        cached = fetch(url, cache_only=True)
        if cached[:4] == b"%PDF":
            return cached
    except CacheMiss:
        pass
    return fetch(url, max_age=None if closed else 86400, delay=POLITE_DELAY)


def _probe_day(
    code: str, day: int, linked: set[int], get: Callable[[str], bytes]
) -> Iterator[tuple[str, bytes | Exception]]:
    """(url, PDF bytes or the error) for each roll call of a session day, numbered from 1. Probing stops at
    the first missing number past the highest one the XML links; a linked number that fails is yielded as an
    error so it lands in the raw table."""
    last_linked = max(linked, default=0)
    number = 1
    while True:
        url = _rollcall_url(code, day, number)
        try:
            data: bytes | Exception = get(url)
        except Exception as exc:
            data = exc
        if isinstance(data, bytes) and data[:4] == b"%PDF":
            yield url, data
        elif number in linked:
            yield url, data if isinstance(data, Exception) else ValueError("not a pdf")
        elif number > last_linked:
            if isinstance(data, Exception):
                log.warning("mo_house.rollcall_probe_failed", url=url, error=str(data))
            return
        number += 1


def _parse_rollcall_pdf(data: bytes) -> tuple[dict, list[tuple[str, str]]]:
    text = "\n".join(pdftext.page_texts(data, layout=True))
    header = {k: (m.group(1) if (m := rx.search(text)) else None) for k, rx in HEADER_FIELDS.items()}
    header["text"] = text.split("Total Yes")[0][:1500] if "Total Yes" in text else text[:1500]
    totals = dict(re.findall(r"Total (Yes|No|Present|Absent)\s*:\s*(\d+)", text))
    header["totals"] = totals
    votes = []
    for line in text.splitlines():
        votes.extend((code, re.sub(r"\s+", " ", name).strip()) for code, name in VOTE_TOKEN.findall(line))
    return header, votes


@loader("mo_house", service="documents.house.mo.gov", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: each session's XML documents (by session code) and each session day's roll-call PDFs (by
    session code and day). Every shard reads every session's XML (cached) to learn which days to probe."""
    with db.JsonSink(shard, source_url=BASE, tables=TABLES) as sink:
        linked: dict[str, dict[int, set[int]]] = {}  # session code -> day -> roll-call numbers the XML links
        codes = [f"{year % 100:02d}{t}" for year in window_years() for t in SESSION_TYPES]
        progress = obs.Progress("sessions", len(codes), log)
        for code in codes:
            files = _session_files(code, 2000 + int(code[:2]))
            progress.tick()
            if files:
                linked.setdefault(code, defaultdict(set))
            owned = shard.owns(code)
            for name, xml in files.items():
                for url in _links(xml, "RollCallPDF"):
                    if m := ROLLCALL_URL.search(url):
                        linked.setdefault(m.group(1), defaultdict(set))[int(m.group(2))].add(int(m.group(3)))
                    else:
                        log.warning("mo_house.rollcall_url_unexpected", url=url)
                if not owned:
                    continue
                stem = name.removesuffix(".XML")
                sess, _, item = stem.partition("-")
                if item.isdigit():
                    table, key, extra = "mo_house_members", f"{sess}-{item}", {"district": item}
                elif item.endswith("LIST"):
                    table, key, extra = "mo_house_lists", stem, {"list": item}
                elif re.match(r"^H[A-Z]*\d+$", item):
                    table, key, extra = "mo_house_bills", stem, {"bill": item}
                else:
                    continue
                sink.add(table, key, {"session_code": sess, **extra, "doc": xmljson.parse(xml)})
        progress.finish()

        days = [
            (code, day)
            for code, by_day in sorted(linked.items())
            for day in range(1, (max(by_day) + DAY_SLACK if by_day else DAYS_IF_UNKNOWN) + 1)
        ]
        mine = shard.take(days, key=lambda unit: f"{unit[0]}-{unit[1]:03d}")
        progress = obs.Progress("session days", len(mine), log)
        for code, day in mine:
            progress.tick()
            closed = 2000 + int(code[:2]) < date.today().year
            for url, data in _probe_day(code, day, linked[code][day], partial(_fetch_rollcall, closed=closed)):
                if isinstance(data, Exception):
                    sink.add("mo_house_rollcalls", url, {"session_code": code, "url": url, "error": str(data)})
                    continue
                header, cast = _parse_rollcall_pdf(data)
                sink.add("mo_house_rollcalls", url, {"session_code": code, "url": url, **header, "n_tokens": len(cast)})
                for i, (c, n) in enumerate(cast):
                    sink.add(
                        "mo_house_rollcall_votes",
                        f"{url}#{i}",
                        {"session_code": code, "url": url, "vote_code": c, "member_token": n},
                    )
        progress.finish()
    return sink.counts
