"""Missouri Ethics Commission campaign finance, via the Accountability Project (TAP) public mirror.

TAP (Investigative Reporting Workshop) republishes MEC's itemized contributions, expenditures and
lobbyist expenditures as cleaned CSVs on a public S3 bucket. Coverage ends in 2022; the opt-in
`mec` loader covers recent years straight from MEC.
"""

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

BUCKET = "https://publicaccountability.s3.amazonaws.com/csv"
FILES = {
    "tap_mec_contributions": ["mo_contribs_clean.csv", "mo_contribs_clean_2020-2022.csv"],
    "tap_mec_expenditures": ["mo_expends_clean.csv"],
    "tap_mec_lobbyist_expenditures": ["mo_lob_exp_combined_clean.csv"],
}


@loader("tap_mec")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: the mirror's CSV files."""
    counts = {}
    for table, names in FILES.items():
        paths = [fetch_to_file(f"{BUCKET}/{n}", CACHE_DIR / "tap" / n, max_age=30 * 86400) for n in shard.take(names)]
        counts[table] = db.replace_csv(table, paths, ignore_errors=True, strict_mode=False, shard=shard)
    return counts
