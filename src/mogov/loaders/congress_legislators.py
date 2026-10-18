"""unitedstates/congress-legislators: every member of Congress ever, with term history and cross-IDs
(bioguide, FEC, OpenSecrets, Vote Smart, ICPSR for Voteview)."""

import json

from mogov import db
from mogov.http import fetch
from mogov.loaders import loader

BASE = "https://unitedstates.github.io/congress-legislators"


@loader("congress_legislators")
def load() -> dict[str, int]:
    counts = {}
    for status in ("current", "historical"):
        url = f"{BASE}/legislators-{status}.json"
        people = json.loads(fetch(url))
        # Land only people who ever represented Missouri; the rest of the country is noise here.
        mo = [p for p in people if any(t.get("state") == "MO" for t in p.get("terms", []))]
        counts[f"congress_legislators_{status}"] = db.replace_json(
            f"congress_legislators_{status}", ((p["id"]["bioguide"], p) for p in mo), source_url=url
        )
    return counts
