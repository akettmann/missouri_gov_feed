"""Shor-McCarty state legislator ideology scores (Harvard Dataverse doi:10.7910/DVN/SGOQ7G, CC BY-NC-SA 4.0).

One career ideal point (np_score; negative = liberal, positive = conservative) per legislator,
1993-2022, with wide per-year chamber/district columns that dbt reshapes.
"""

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

# Tab-delimited export of the January 2025 release.
URL = "https://dataverse.harvard.edu/api/access/datafile/10853698"


@loader("shor_mccarty")
def load() -> dict[str, int]:
    path = fetch_to_file(URL, CACHE_DIR / "shor_mccarty" / "shor_mccarty.tab", max_age=90 * 86400)
    return {"shor_mccarty": db.replace_csv("shor_mccarty", path, delim="\t")}
