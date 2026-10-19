"""Missouri House of Representatives: official XML exports + per-roll-call vote PDFs.

- documents.house.mo.gov/xml/{session}.zip for closed sessions; per-file XML for the open one.
  Members (roster, committees, bio, sponsored bills) and bills (sponsors, actions, roll-call totals).
- Roll-call PDFs (2014+) are the only per-member House vote record. Each is parsed into one raw
  row per (roll call, member token); tokens are surnames like "SMITH 46" or "MR SPEAKER" and are
  matched to members in dbt.

The site asks that automated clients poll its XML no more than every 30 minutes; caching is a day.
"""

import io
import re
import zipfile
from datetime import date

from mogov import db, obs, pdftext, xmljson
from mogov.config import window_years
from mogov.http import fetch
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
TABLES = ["mo_house_members", "mo_house_bills", "mo_house_lists", "mo_house_rollcalls", "mo_house_rollcall_votes"]


def _is_xml(data: bytes) -> bool:
    return data.lstrip()[:1] == b"<" and not data.lstrip()[:15].lower().startswith(b"<!doctype html")


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
    for kind in ("MemberList", "BillList", "SenateActList"):
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
        for link in re.findall(rf"<{link_tag}>([^<]+)</{link_tag}>".encode(), listing):
            url = link.decode().strip()
            files[url.rsplit("/", 1)[-1].upper()] = fetch(url, delay=POLITE_DELAY)
    return files


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
    """Units: each session's XML documents (by session code) and each roll-call PDF (by URL). Every shard
    reads every session's XML (cached) to list the roll calls."""
    with db.JsonSink(shard, source_url=BASE, tables=TABLES) as sink:
        rollcall_urls: dict[str, str] = {}
        codes = [f"{year % 100:02d}{t}" for year in window_years() for t in SESSION_TYPES]
        progress = obs.Progress("sessions", len(codes), log)
        for code in codes:
            files = _session_files(code, 2000 + int(code[:2]))
            progress.tick()
            owned = shard.owns(code)
            for name, xml in files.items():
                for url in re.findall(rb"<RollCallPDF>([^<]+)</RollCallPDF>", xml):
                    rollcall_urls.setdefault(url.decode().strip(), code)
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

        mine = shard.take(sorted(rollcall_urls))
        progress = obs.Progress("roll-call PDFs", len(mine), log)
        for url in mine:
            sess = rollcall_urls[url]
            progress.tick()
            try:
                data = fetch(url, max_age=None, delay=POLITE_DELAY)  # roll calls never change once posted
            except Exception as exc:
                sink.add("mo_house_rollcalls", url, {"session_code": sess, "url": url, "error": str(exc)})
                continue
            if data[:4] != b"%PDF":
                sink.add("mo_house_rollcalls", url, {"session_code": sess, "url": url, "error": "not a pdf"})
                continue
            header, cast = _parse_rollcall_pdf(data)
            sink.add("mo_house_rollcalls", url, {"session_code": sess, "url": url, **header, "n_tokens": len(cast)})
            for i, (c, n) in enumerate(cast):
                sink.add(
                    "mo_house_rollcall_votes",
                    f"{url}#{i}",
                    {"session_code": sess, "url": url, "vote_code": c, "member_token": n},
                )
        progress.finish()
    return sink.counts
