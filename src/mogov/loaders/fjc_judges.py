"""Federal Judicial Center Biographical Directory of Article III judges (all federal judges since 1789):
appointments, appointing president/party, ABA rating, terminations, and a professional-career narrative."""

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

URL = "https://www.fjc.gov/sites/default/files/history/judges.csv"


@loader("fjc_judges")
def load(shard: db.Shard) -> dict[str, int]:
    """One unit: the directory CSV."""
    paths = [fetch_to_file(URL, CACHE_DIR / "fjc" / "judges.csv", max_age=30 * 86400)] if shard.owns("fjc") else []
    return {"fjc_judges": db.replace_csv("fjc_judges", paths, normalize_names=False, shard=shard)}
