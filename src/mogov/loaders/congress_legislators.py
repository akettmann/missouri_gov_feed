"""unitedstates/congress-legislators: every member of Congress ever, with term history and cross-IDs
(bioguide, FEC, OpenSecrets, Vote Smart, ICPSR for Voteview)."""

import json

from mogov import db
from mogov.http import fetch
from mogov.loaders import loader

BASE = "https://unitedstates.github.io/congress-legislators"


@loader("congress_legislators", service="unitedstates.github.io")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: the current and historical files."""
    counts = {}
    for status in ("current", "historical"):
        url, table = f"{BASE}/legislators-{status}.json", f"congress_legislators_{status}"
        people = json.loads(fetch(url)) if shard.owns(table) else []
        # Land only people who ever represented Missouri; the rest of the country is noise here.
        mo = (p for p in people if any(t.get("state") == "MO" for t in p.get("terms", [])))
        counts[table] = db.replace_json(table, ((p["id"]["bioguide"], p) for p in mo), source_url=url, shard=shard)
    return counts
