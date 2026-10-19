"""Voteview: congressional roll calls, individual votes, and DW-NOMINATE ideology scores."""

import os

from mogov import db
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file
from mogov.loaders import loader

BASE = "https://voteview.com/static/data/out"
# Congresses to pull; 119th = 2025-2027. Override with e.g. MOGOV_VOTEVIEW_CONGRESSES=115,116,117,118,119
CONGRESSES = [int(c) for c in os.environ.get("MOGOV_VOTEVIEW_CONGRESSES", "117,118,119").split(",")]


@loader("voteview", service="voteview.com")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: one CSV per (kind, congress)."""
    counts = {}
    for kind in ("members", "rollcalls", "votes"):
        paths = []
        for congress in CONGRESSES:
            name = f"HS{congress}_{kind}.csv"
            if shard.owns(name):
                # Full-chamber files (HS = both chambers). Votes are filtered to MO members in dbt.
                paths.append(fetch_to_file(f"{BASE}/{kind}/{name}", CACHE_DIR / "voteview" / name))
        counts[f"voteview_{kind}"] = db.replace_csv(f"voteview_{kind}", paths, shard=shard)
    return counts
