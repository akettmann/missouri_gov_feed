"""Voteview: congressional roll calls, individual votes, and DW-NOMINATE ideology scores."""

import os

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

BASE = "https://voteview.com/static/data/out"
# Congresses to pull; 119th = 2025-2027. Override with e.g. MOGOV_VOTEVIEW_CONGRESSES=115,116,117,118,119
CONGRESSES = [int(c) for c in os.environ.get("MOGOV_VOTEVIEW_CONGRESSES", "117,118,119").split(",")]


@loader("voteview")
def load() -> dict[str, int]:
    counts = {}
    for kind in ("members", "rollcalls", "votes"):
        paths = []
        for congress in CONGRESSES:
            # Full-chamber files (HS = both chambers). Votes are filtered to MO members in dbt.
            url = f"{BASE}/{kind}/HS{congress}_{kind}.csv"
            paths.append(fetch_to_file(url, CACHE_DIR / "voteview" / f"HS{congress}_{kind}.csv"))
        counts[f"voteview_{kind}"] = db.replace_csv(f"voteview_{kind}", paths)
    return counts
