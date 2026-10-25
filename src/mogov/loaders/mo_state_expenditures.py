"""Missouri state expenditures (data.mo.gov "<fiscal year> State Expenditures", the Missouri Accountability
Portal's spending data): what each state agency paid each payee in a fiscal year (July to June), per category
and detail line. Legislators' per diem (LEGISLATIVE DAILY EXPENSE ALLOWANCE) and mileage are on it under the
agency LEGISLATURE, as are payments to vendors by every agency.

A row is one payee's annual total for one agency and detail line, not one payment. Rows land verbatim (every
agency, every payee), so the vendor payments are there for later use; dbt picks out the legislators.
One dataset per fiscal year, paged through the Socrata API in a stable row order; their ids come from the
Socrata catalog. Terms: https://mo.gov/data-policy (see docs/sources.md).
"""

import json
import re
from datetime import date

from mogov import db, obs
from mogov.config import window_years
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

DOMAIN = "data.mo.gov"
CATALOG = "https://api.us.socrata.com/api/catalog/v1"
PAGE_SIZE = 50_000
PAGE_DELAY = 0.5  # seconds between uncached page requests; a state-run site


def _datasets() -> dict[int, str]:
    """{fiscal year: Socrata dataset id} for the "<year> State Expenditures" datasets."""
    body = json.loads(fetch(CATALOG, {"domains": DOMAIN, "q": "State Expenditures", "limit": 100}, max_age=7 * 86400))
    out = {}
    for result in body["results"]:
        m = re.fullmatch(r"(\d{4}) State Expenditures", result["resource"]["name"].strip())
        if m:
            out[int(m.group(1))] = result["resource"]["id"]
    return out


def _max_age(year: int) -> float:
    # the current fiscal year (July to June) is replaced as payments post; closed years can still be corrected
    return (7 if year >= date.today().year - 1 else 30) * 86400


def _count(year: int, dataset: str) -> int:
    url = f"https://{DOMAIN}/resource/{dataset}.json"
    return int(json.loads(fetch(url, {"$select": "count(*)"}, max_age=_max_age(year)))[0]["count"])


def _pages(year: int, dataset: str, total: int):
    """Yield (record_key, row) for a fiscal year, in `:id` order so a re-run pages the same rows the same way."""
    url = f"https://{DOMAIN}/resource/{dataset}.json"
    for offset in range(0, total, PAGE_SIZE):
        params = {"$order": ":id", "$limit": PAGE_SIZE, "$offset": offset}
        rows = json.loads(fetch(url, params, max_age=_max_age(year), delay=PAGE_DELAY))
        for n, row in enumerate(rows, start=offset + 1):
            yield f"{year}:{n}", row
        if len(rows) < min(PAGE_SIZE, total - offset):
            raise RuntimeError(f"{dataset}: page at offset {offset} came back short ({len(rows)} rows)")


@loader("mo_state_expenditures", service=DOMAIN)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: fiscal years (one dataset each), within MOGOV_LOOKBACK_YEARS."""
    datasets = _datasets()
    years = [y for y in window_years() if y in datasets and shard.owns(str(y))]
    totals = {y: _count(y, datasets[y]) for y in years}
    progress = obs.Progress("mo_state_expenditures rows", sum(totals.values()))
    with db.JsonSink(shard, source_url=f"https://{DOMAIN}/", tables=["mo_state_expenditures"]) as sink:
        for year in years:
            dataset = datasets[year]
            url = f"https://{DOMAIN}/resource/{dataset}.json"
            for key, row in _pages(year, dataset, totals[year]):
                sink.add("mo_state_expenditures", key, row, source_url=url)
                progress.tick()
            log.info("mo_state_expenditures.year", year=year, dataset=dataset, rows=totals[year])
    progress.finish()
    return {"mo_state_expenditures": sink.counts["mo_state_expenditures"]}
