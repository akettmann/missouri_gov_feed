"""Missouri state payroll (data.mo.gov "<year> State Employee Pay", the Missouri Accountability Portal's
employee data): calendar-year gross pay per employee, agency and position. Legislators, statewide officials
and state judges are on it, so this is the salary source for those officials.

Gross pay is everything paid in the year (a mid-year change of office shows as two rows), not the base
salary. Only the agencies that employ officials are fetched (the Legislature, the Judiciary and the six
statewide offices): the rows land verbatim, staff included, and dbt picks out the officeholders.
One dataset per year; their ids come from the Socrata catalog.
"""

import json
import re
from datetime import date

import httpx

from mogov import db, obs
from mogov.config import CACHE_DIR, window_years
from mogov.http import fetch, fetch_to_file
from mogov.loaders import loader

log = obs.get_logger(__name__)

DOMAIN = "data.mo.gov"
CATALOG = "https://api.us.socrata.com/api/catalog/v1"
AGENCIES = [
    "LEGISLATURE",
    "JUDICIARY",
    "OFFICE OF GOVERNOR",
    "OFFICE OF LIEUTENANT GOVERNOR",
    "OFFICE OF SECRETARY OF STATE",
    "OFFICE OF STATE AUDITOR",
    "OFFICE OF STATE TREASURER",
    "OFFICE OF ATTORNEY GENERAL",
]


def _datasets() -> dict[int, str]:
    """{calendar year: Socrata dataset id} for the "<year> State Employee Pay" datasets."""
    body = json.loads(fetch(CATALOG, {"domains": DOMAIN, "q": "State Employee Pay", "limit": 100}, max_age=7 * 86400))
    out = {}
    for result in body["results"]:
        m = re.fullmatch(r"(\d{4}) State Employee Pay", result["resource"]["name"].strip())
        if m:
            out[int(m.group(1))] = result["resource"]["id"]
    return out


@loader("mo_employee_pay", service=DOMAIN)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: calendar years (one dataset each), within MOGOV_LOOKBACK_YEARS."""
    datasets = _datasets()
    years = [y for y in window_years() if y in datasets and shard.owns(str(y))]
    agencies = ", ".join(f"'{a}'" for a in AGENCIES)
    paths = []
    for year in years:
        url = str(
            httpx.URL(
                f"https://{DOMAIN}/resource/{datasets[year]}.csv",
                params={"$where": f"agency_name in ({agencies})", "$limit": 1_000_000},
            )
        )
        # the current year's dataset is replaced as payroll runs; closed years can still be corrected
        max_age = 7 * 86400 if year >= date.today().year - 1 else 30 * 86400
        paths.append(fetch_to_file(url, CACHE_DIR / "mo_employee_pay" / f"{year}.csv", max_age=max_age))
    log.info("employee_pay.years", years=years)
    return {"mo_employee_pay": db.replace_csv("mo_employee_pay", paths, shard=shard)}
