"""GovInfo BILLSTATUS: federal bills with their sponsor, cosponsors, actions, recorded votes and Public Law number.

https://www.govinfo.gov/bulkdata/BILLSTATUS/{congress}/{type}/BILLSTATUS-{congress}-{type}.zip is one zip per
Congress and bill type (hr, s, hjres, sjres, hconres, sconres, hres, sres); each member is one bill's XML. No key
and no robots.txt rule against /bulkdata. The newest Congress's zips are rebuilt as bills move, so they are
re-downloaded daily, and so are the outgoing Congress's until March 1 (late signings); older zips are re-read
monthly. "Newest" is the Congress in session today (from the date), whatever MOGOV_BILLSTATUS_CONGRESSES lists.
The date is read once per run. The zips are cached under CACHE_DIR (`<MOGOV_DATA_DIR>/cache`);
on Cloud Run Jobs that is the mounted bucket, so the re-fetch rules hold across runs.

Each XML file is landed unchanged as gzip under RAW_DIR/govinfo_billstatus_xml/<congress>/<type>/ and described in
`govinfo_billstatus_files` (path, URL, size, hash, landing time); `mogov.parsers.govinfo_billstatus` parses the same
bytes with lxml into one row per bill, sponsor, cosponsor, action, recorded vote and law. Everything is landed, not
just Missouri's members: sponsors are matched to Missouri's delegation by `bioguideId` in dbt.

Units: (congress, bill type) zips, so a shard downloads only the zips it owns (no file is fetched by two shards).
The House `hr` zip is the biggest by far (33 MB); shard counts above the number of zips (8 per Congress) gain nothing.
Congresses: MOGOV_BILLSTATUS_CONGRESSES (default: the 117th to the one in session today);
types: MOGOV_BILLSTATUS_TYPES.
"""

import gzip
import hashlib
import os
import zipfile
from datetime import UTC, date, datetime

import httpx

from mogov import db, obs
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file, write_atomic
from mogov.loaders import loader
from mogov.parsers import govinfo_billstatus as parser

log = obs.get_logger(__name__)

BASE = "https://www.govinfo.gov/bulkdata/BILLSTATUS"
FIRST_CONGRESS = 117  # start of the default window (the end follows the date); how far back to go is #621
_configured = os.environ.get("MOGOV_BILLSTATUS_CONGRESSES")
CONGRESSES: list[int] | None = [int(c) for c in _configured.split(",")] if _configured else None  # None: the default
BILL_TYPES = os.environ.get("MOGOV_BILLSTATUS_TYPES", "hr,s,hjres,sjres,hconres,sconres,hres,sres").split(",")
XML_DIR = "govinfo_billstatus_xml"  # under RAW_DIR: <congress>/<type>/<FILE>.xml.gz
FILES_TABLE = "govinfo_billstatus_files"
TABLES = [FILES_TABLE, *parser.ALL_TABLES]


def congress_on(day: date) -> int:
    """The Congress in session on `day`: the 119th began 2025-01-03, each Congress lasts two years and begins on
    January 3 of an odd year (the days before that still belong to the previous one). The switch is on whole UTC
    dates, so it comes about 17 hours before noon ET on January 3, when the new Congress is sworn in."""
    year = day.year - 1 if day.year % 2 == 1 and (day.month, day.day) < (1, 3) else day.year
    return (year - 1789) // 2 + 1


DAILY = 86400
MONTHLY = 30 * 86400
OUTGOING_GRACE_END = (3, 1)  # (month, day): the outgoing Congress keeps its daily refresh until this date


def max_age(congress: int, day: date) -> int:
    """Seconds a cached zip stays fresh on `day`. The Congress in session (from the date, not from which Congresses
    are configured: a run that leaves out the newest one must not mistake an older one for the live one) is daily.
    So is the one just ended until March 1 of the new Congress's first year: signings, vetoes and Public Law
    numbers for the last bills often land after January 3. Every other Congress is monthly."""
    current = congress_on(day)
    if congress == current:
        return DAILY
    first_year = 1789 + 2 * (current - 1)  # a Congress starts in the odd year after 1788 + 2n
    if congress == current - 1 and day.year == first_year and (day.month, day.day) < OUTGOING_GRACE_END:
        return DAILY
    return MONTHLY


def default_congresses(day: date) -> list[int]:
    """FIRST_CONGRESS through the Congress in session on `day`, so the newest one is picked up on its first day
    without a config change (on 2027-01-03 the 120th joins and the 119th, now a finished Congress, goes monthly)."""
    return list(range(FIRST_CONGRESS, congress_on(day) + 1))


def zip_url(congress: int, bill_type: str) -> str:
    return f"{BASE}/{congress}/{bill_type}/BILLSTATUS-{congress}-{bill_type}.zip"


def land_file(congress: int, bill_type: str, name: str, xml: bytes, url: str) -> dict:
    """Write one XML file, byte for byte, as gzip under the raw dir (the same bytes every run, so a re-run
    rewrites nothing) and describe it for the files table."""
    rel = f"{XML_DIR}/{congress}/{bill_type}/{name}.gz"
    gz = gzip.compress(xml, mtime=0)
    dest = db.RAW_DIR / rel
    if not (dest.exists() and dest.read_bytes() == gz):
        write_atomic(dest, gz)
    return {
        "congress": congress,
        "bill_type": bill_type,
        "file_name": name,
        "source_url": url,
        "path": rel,
        "size_bytes": len(xml),
        "gz_bytes": len(gz),
        "sha256": hashlib.sha256(xml).hexdigest(),
        "landed_at": datetime.now(UTC).isoformat(),
    }


@loader("govinfo_billstatus", service="www.govinfo.gov", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: one zip per (congress, bill type). Streams each zip member by member."""
    today = datetime.now(UTC).date()  # read once: a run straddling midnight must not see two "current" Congresses
    units = [(c, t) for c in (CONGRESSES or default_congresses(today)) for t in BILL_TYPES]
    mine = shard.take(units, key=lambda u: f"{u[0]}-{u[1]}")
    progress = obs.Progress("zips", len(mine), log)
    with db.JsonSink(shard, source_url=BASE, tables=TABLES) as sink:
        for congress, bill_type in mine:
            url = zip_url(congress, bill_type)
            dest = CACHE_DIR / "govinfo_billstatus" / f"BILLSTATUS-{congress}-{bill_type}.zip"
            age = max_age(congress, today)
            try:
                fetch_to_file(url, dest, max_age=age)
            except httpx.HTTPStatusError as e:
                if e.response.status_code != 404:
                    raise
                log.warning("govinfo_billstatus.zip_missing", url=url)
                progress.tick()
                continue
            n_files = 0
            with zipfile.ZipFile(dest) as zf:
                for name in sorted(zf.namelist()):
                    if not name.lower().endswith(".xml"):
                        continue
                    xml = zf.read(name)
                    base = name.rsplit("/", 1)[-1]
                    member_url = f"{url}#{name}"
                    sink.add(
                        FILES_TABLE, base, land_file(congress, bill_type, base, xml, member_url), source_url=member_url
                    )
                    errors: list[str] = []
                    rows = parser.parse_bill(xml, base, errors)
                    if errors:
                        log.warning("govinfo_billstatus.xml_recovered", file=base, errors=len(errors), first=errors[0])
                    for key, entity_rows in rows.items():
                        for record_key, payload in entity_rows:
                            sink.add(parser.TABLES[key], record_key, payload, source_url=member_url)
                    n_files += 1
            log.info("govinfo_billstatus.zip_done", congress=congress, bill_type=bill_type, files=n_files)
            progress.tick()
        progress.finish()
    return sink.counts
