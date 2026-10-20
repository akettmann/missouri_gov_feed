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


def _latest_snapshot() -> str:
    listing = fetch(f"{BUCKET}/", {"list-type": "2", "prefix": "bulk-data/people-db-people-"}).decode()
    dates = re.findall(r"people-db-people-(\d{4}-\d{2}-\d{2})\.csv\.bz2", listing)
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
