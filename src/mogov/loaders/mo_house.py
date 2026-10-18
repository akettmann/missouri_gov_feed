"""Missouri House of Representatives: official XML exports + per-roll-call vote PDFs.

- documents.house.mo.gov/xml/{session}.zip for closed sessions; per-file XML for the open one.
  Members (roster, committees, bio, sponsored bills) and bills (sponsors, actions, roll-call totals).
- Roll-call PDFs (2014+) are the only per-member House vote record. Each is parsed into one raw
  row per (roll call, member token); tokens are surnames like "SMITH 46" or "MR SPEAKER" and are
  matched to members in dbt.

The site asks that automated clients poll its XML no more than every 30 minutes; caching is a day.
"""

import io
import os
import re
import zipfile

import pdfplumber

from mogov import db, xmljson
from mogov.http import fetch
from mogov.loaders import loader

BASE = "https://documents.house.mo.gov"
# Session codes: two-digit year + type (1 = regular, 3/4 = 1st/2nd extraordinary).
SESSIONS = os.environ.get("MOGOV_HOUSE_SESSIONS", "231,241,251,253,254,261").split(",")
POLITE_DELAY = 0.3

VOTE_TOKEN = re.compile(r"(?<![A-Z])([YNP@]) +- +([A-Z][A-Z'.\- ]*?[A-Z.](?: \d{1,3})?)(?=\s{2,}|\s+[YNP@] +- |\s*$)")
HEADER_FIELDS = {
    "session_day": re.compile(r"Session Day\s*:\s*(\d+)"),
    "vote_date": re.compile(r"Date\s*:\s*(\d{1,2}/\d{1,2}/\d{4})"),
    "rollcall_number": re.compile(r"Roll Call\s*:\s*(\d+)"),
}


def _session_files(code: str) -> dict[str, bytes]:
    """All XML files for a House session, keyed by upper-cased file name."""
    data = fetch(f"{BASE}/xml/{code}.zip", max_age=7 * 86400, delay=POLITE_DELAY)
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            return {
                name.rsplit("/", 1)[-1].upper(): zf.read(name)
                for name in zf.namelist()
                if name.lower().endswith(".xml")
            }
    # Open session: no zip yet, walk the list files.
    files: dict[str, bytes] = {}
    for kind in ("MemberList", "BillList", "SenateActList"):
        try:
            files[f"{code}-{kind}.XML".upper()] = fetch(f"{BASE}/xml/{code}-{kind}.XML", delay=POLITE_DELAY)
        except Exception:
            continue
    for kind, link_tag in (("MemberList", "RepresentativeXMLLink"), ("BillList", "BillXMLLink")):
        listing = files.get(f"{code}-{kind}.XML".upper())
        if not listing:
            continue
        for link in re.findall(rf"<{link_tag}>([^<]+)</{link_tag}>".encode(), listing):
            url = link.decode().strip()
            files[url.rsplit("/", 1)[-1].upper()] = fetch(url, delay=POLITE_DELAY)
    return files


def _parse_rollcall_pdf(data: bytes) -> tuple[dict, list[tuple[str, str]]]:
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        text = "\n".join(page.extract_text(layout=True) or "" for page in pdf.pages)
    header = {k: (m.group(1) if (m := rx.search(text)) else None) for k, rx in HEADER_FIELDS.items()}
    header["text"] = text.split("Total Yes")[0][:1500] if "Total Yes" in text else text[:1500]
    totals = dict(re.findall(r"Total (Yes|No|Present|Absent)\s*:\s*(\d+)", text))
    header["totals"] = totals
    votes = []
    for line in text.splitlines():
        votes.extend((code, re.sub(r"\s+", " ", name).strip()) for code, name in VOTE_TOKEN.findall(line))
    return header, votes


@loader("mo_house")
def load() -> dict[str, int]:
    members, bills, lists, rollcall_urls = [], [], [], {}
    for code in SESSIONS:
        code = code.strip()
        for name, xml in _session_files(code).items():
            stem = name.removesuffix(".XML")
            sess, _, item = stem.partition("-")
            obj = xmljson.parse(xml)
            if item.isdigit():
                members.append((f"{sess}-{item}", {"session_code": sess, "district": item, "doc": obj}))
            elif item.endswith("LIST"):
                lists.append((stem, {"session_code": sess, "list": item, "doc": obj}))
            elif re.match(r"^H[A-Z]*\d+$", item):
                bills.append((stem, {"session_code": sess, "bill": item, "doc": obj}))
            for url in re.findall(rb"<RollCallPDF>([^<]+)</RollCallPDF>", xml):
                rollcall_urls.setdefault(url.decode().strip(), sess)

    rollcalls, votes = [], []
    for url, sess in sorted(rollcall_urls.items()):
        try:
            data = fetch(url, max_age=None, delay=POLITE_DELAY)  # roll calls never change once posted
        except Exception as exc:
            rollcalls.append((url, {"session_code": sess, "url": url, "error": str(exc)}))
            continue
        if data[:4] != b"%PDF":
            rollcalls.append((url, {"session_code": sess, "url": url, "error": "not a pdf"}))
            continue
        header, cast = _parse_rollcall_pdf(data)
        rollcalls.append((url, {"session_code": sess, "url": url, **header, "n_tokens": len(cast)}))
        votes.extend(
            (f"{url}#{i}", {"session_code": sess, "url": url, "vote_code": c, "member_token": n})
            for i, (c, n) in enumerate(cast)
        )

    return {
        "mo_house_members": db.replace_json("mo_house_members", members, source_url=BASE),
        "mo_house_bills": db.replace_json("mo_house_bills", bills, source_url=BASE),
        "mo_house_lists": db.replace_json("mo_house_lists", lists, source_url=BASE),
        "mo_house_rollcalls": db.replace_json("mo_house_rollcalls", rollcalls, source_url=BASE),
        "mo_house_rollcall_votes": db.replace_json("mo_house_rollcall_votes", votes, source_url=BASE),
    }
