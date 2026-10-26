r"""CourtListener (Free Law Project) quarterly bulk exports: judges, their positions, and federal judges'
financial disclosures (AO-10 reports, parsed into investments, gifts, debts, outside positions...).

Public S3 bucket, no auth. Files are bz2-compressed Postgres CSV exports with ESCAPE '\': quotes inside
fields are backslash-escaped, not doubled, so the dialect is set explicitly (left to sniffing, DuckDB lost
rows and choked on the reimbursements file). They're decompressed to the cache and landed verbatim.
Filtering to Missouri courts (mo, moctapp*, moed, mowd, ca8...) happens in dbt.
"""

import bz2
import re
import shutil

from lxml import etree

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch, fetch_to_file
from mogov.loaders import loader

BUCKET = "https://com-courtlistener-storage.s3-us-west-2.amazonaws.com"
TABLES = {
    "courts": "cl_courts",
    "people-db-people": "cl_people",
    "people-db-positions": "cl_positions",
    "people-db-political-affiliations": "cl_political_affiliations",
    "people-db-educations": "cl_educations",
    "people-db-schools": "cl_schools",
    "people-db-retention-events": "cl_retention_events",
    "financial-disclosures": "cl_financial_disclosures",
    "financial-disclosure-investments": "cl_fd_investments",
    "financial-disclosures-gifts": "cl_fd_gifts",
    "financial-disclosures-debts": "cl_fd_debts",
    "financial-disclosures-positions": "cl_fd_positions",
    "financial-disclosures-agreements": "cl_fd_agreements",
    "financial-disclosures-non-investment-income": "cl_fd_non_investment_income",
    "financial-disclosures-spousal-income": "cl_fd_spousal_income",
    "financial-disclosures-reimbursements": "cl_fd_reimbursements",
}


_SNAPSHOT_KEY = re.compile(r"^bulk-data/people-db-people-(\d{4}-\d{2}-\d{2})\.csv\.bz2$")


def _parse_listing(raw: bytes) -> tuple[list[str], str | None]:
    """Return (object keys, next continuation token or None) from one S3 ListObjectsV2 XML page.

    Hardened parser settings and local-name selection (the response is namespaced); same settings as the
    other XML loaders so a later cleanup can unify them behind one helper.
    """
    parser = etree.XMLParser(recover=True, resolve_entities=False, no_network=True, huge_tree=True)
    root = etree.fromstring(raw, parser)
    if root is None:
        return [], None
    keys, token, truncated = [], None, False
    for el in root:
        if not isinstance(el.tag, str):  # comments, processing instructions
            continue
        name = etree.QName(el).localname
        if name == "Contents":
            keys += [(k.text or "").strip() for k in el if isinstance(k.tag, str) and etree.QName(k).localname == "Key"]
        elif name == "IsTruncated":
            truncated = (el.text or "").strip().lower() == "true"
        elif name == "NextContinuationToken":
            token = (el.text or "").strip() or None
    return keys, (token if truncated else None)


def _latest_snapshot() -> str:
    params = {"list-type": "2", "prefix": "bulk-data/people-db-people-"}
    dates: list[str] = []
    while True:
        keys, token = _parse_listing(fetch(f"{BUCKET}/", params))
        dates += [m.group(1) for k in keys if (m := _SNAPSHOT_KEY.match(k))]
        if token is None:
            break
        params = {**params, "continuation-token": token}
    if not dates:
        raise RuntimeError("no CourtListener people snapshot found in bucket listing")
    return max(dates)


@loader("courtlistener_bulk", service="courtlistener-s3")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: one export file per table."""
    snap = _latest_snapshot()
    counts = {}
    for stem, table in TABLES.items():
        if not shard.owns(table):
            counts[table] = db.replace_csv(table, [], shard=shard)
            continue
        name = f"{stem}-{snap}.csv"
        bz_path = fetch_to_file(
            f"{BUCKET}/bulk-data/{name}.bz2", CACHE_DIR / "courtlistener" / f"{name}.bz2", max_age=None
        )
        csv_path = bz_path.with_suffix("")
        if not csv_path.exists():
            with bz2.open(bz_path, "rb") as src, csv_path.open("wb") as dst:
                shutil.copyfileobj(src, dst, 1 << 20)
        counts[table] = db.replace_csv(
            table, csv_path, quote='"', escape="\\", strict_mode=False, parallel=False, shard=shard
        )
    return counts
