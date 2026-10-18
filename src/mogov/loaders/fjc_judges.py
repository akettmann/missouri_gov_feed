"""Federal Judicial Center Biographical Directory of Article III judges (all federal judges since 1789):
appointments, appointing president/party, ABA rating, terminations, and a professional-career narrative."""

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

URL = "https://www.fjc.gov/sites/default/files/history/judges.csv"


@loader("fjc_judges")
def load() -> dict[str, int]:
    path = fetch_to_file(URL, CACHE_DIR / "fjc" / "judges.csv", max_age=30 * 86400)
    return {"fjc_judges": db.replace_csv("fjc_judges", path, normalize_names=False)}
