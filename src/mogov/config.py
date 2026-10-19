import os
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
# Repo-root .env (gitignored) supplies keys/contact; real environment variables take precedence.
load_dotenv(ROOT / ".env", override=False)
DATA_DIR = Path(os.environ.get("MOGOV_DATA_DIR", ROOT / "data"))
CACHE_DIR = DATA_DIR / "cache"
RAW_DIR = Path(os.environ.get("MOGOV_RAW_DIR", DATA_DIR / "raw"))
DB_PATH = Path(os.environ.get("MOGOV_DB", DATA_DIR / "mogov.duckdb"))
DBT_DIR = ROOT / "dbt"

# Contact info (email or URL) for the User-Agent. Some sources (Wikimedia, SEC EDGAR) require it;
# loaders for those sources skip themselves when it isn't set. Never defaulted to anyone's address.
CONTACT = os.environ.get("MOGOV_CONTACT", "").strip()
USER_AGENT = os.environ.get(
    "MOGOV_USER_AGENT",
    f"missouri-gov-feed/0.1 (public-records research; {CONTACT})"
    if CONTACT
    else "missouri-gov-feed/0.1 (public-records research)",
)
FEC_API_KEY = os.environ.get("FEC_API_KEY", "DEMO_KEY")

# Coverage window for year-windowed state sources (MO House roll calls, MO Senate journals): this many
# calendar years ending with the current one. House roll-call PDFs go back to 2014.
LOOKBACK_YEARS = int(os.environ.get("MOGOV_LOOKBACK_YEARS", "10"))


def window_years() -> list[int]:
    this_year = date.today().year
    return list(range(this_year - LOOKBACK_YEARS + 1, this_year + 1))
