"""Census Gazetteer ZIP Code Tabulation Areas (ZCTAs): each ZCTA's internal point (lat/lon) and land and water
area, for the frontend's "find my officials by ZIP code" lookup.

One national file (about 33,000 rows) per vintage, landed verbatim; dbt keeps Missouri's
(ZCTAs 630xx-658xx). ZCTAs approximate USPS ZIP codes from census blocks, so a few PO-box-only ZIPs have no
ZCTA. Older vintages were tab-separated and 2026 is pipe-separated, so the delimiter is sniffed, not fixed.
"""

import zipfile
from datetime import date

from mogov import db, obs
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://www2.census.gov/geo/docs/maps-data/data/gazetteer"
VINTAGES_BACK = 3


def _download():
    """Newest vintage whose zip downloads; a vintage's file doesn't change once published."""
    this_year = date.today().year
    for year in range(this_year, this_year - VINTAGES_BACK, -1):
        name = f"{year}_Gaz_zcta_national.zip"
        url = f"{BASE}/{year}_Gazetteer/{name}"
        try:
            path = fetch_to_file(url, CACHE_DIR / "census_zcta" / name, max_age=None)
        except Exception as e:  # not published yet for this year
            log.info("census_zcta.vintage_missing", year=year, error=str(e))
            continue
        if zipfile.is_zipfile(path):
            return url, path
        log.warning("census_zcta.not_a_zip", url=url, effect="trying the previous vintage")
        path.unlink(missing_ok=True)
    raise RuntimeError(f"no Gazetteer ZCTA file in the last {VINTAGES_BACK} vintages")


@loader("census_zcta", service="www2.census.gov")
def load(shard: db.Shard) -> dict[str, int]:
    """One unit: the national Gazetteer ZCTA file."""
    if not shard.owns("census_zcta"):
        return {"census_zcta_gazetteer": db.replace_csv("census_zcta_gazetteer", [], shard=shard)}
    url, path = _download()
    with zipfile.ZipFile(path) as zf:
        member = next(n for n in zf.namelist() if n.endswith(".txt"))
        txt = CACHE_DIR / "census_zcta" / member
        txt.write_bytes(zf.read(member))
    log.info("census_zcta.file", url=url, member=member)
    return {"census_zcta_gazetteer": db.replace_csv("census_zcta_gazetteer", [txt], normalize_names=True, shard=shard)}
