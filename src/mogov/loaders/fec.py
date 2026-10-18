"""FEC campaign finance for federal candidates/committees (Missouri's congressional delegation).

Keyless bulk files (fec.gov/files/bulk-downloads), landed nationally and filtered in dbt:
  cn  candidate master          cm  committee master (CMTE_DSGN = 'D' -> leadership PAC)
  ccl candidate-committee links  pas2 committee -> candidate contributions (both directions:
  weball candidate summary totals    PACs giving TO our members, our members' PACs giving FROM)

Optional:
  MOGOV_FEC_INDIV=1   also land the individual-contributions file (~2.3 GB zipped per cycle).
  FEC_API_KEY=<key>   pull API aggregates of each member's itemized donors by employer, size and state.
                      DEMO_KEY only allows ~10 calls/hour, so aggregates are skipped without a real key
                      (free at https://api.data.gov/signup/).
"""

import json
import os
import zipfile

from mogov import db
from mogov.config import CACHE_DIR, FEC_API_KEY
from mogov.http import fetch, fetch_to_file
from mogov.loaders import loader

BULK = "https://www.fec.gov/files/bulk-downloads"
API = "https://api.open.fec.gov/v1"
CYCLES = [int(c) for c in os.environ.get("MOGOV_FEC_CYCLES", "2022,2024,2026").split(",")]

# (bulk file stem, raw table, header dictionary name)
FILES = [
    ("cn", "fec_candidates", "cn"),
    ("cm", "fec_committees", "cm"),
    ("ccl", "fec_cand_cmte_links", "ccl"),
    ("pas2", "fec_committee_contribs_to_candidates", "pas2"),
    ("weball", "fec_candidate_summary", None),
]
# weball has no published header file; columns per https://www.fec.gov/campaign-finance-data/all-candidates-file-description/
WEBALL_COLUMNS = [
    "CAND_ID",
    "CAND_NAME",
    "CAND_ICI",
    "PTY_CD",
    "CAND_PTY_AFFILIATION",
    "TTL_RECEIPTS",
    "TRANS_FROM_AUTH",
    "TTL_DISB",
    "TRANS_TO_AUTH",
    "COH_BOP",
    "COH_COP",
    "CAND_CONTRIB",
    "CAND_LOANS",
    "OTHER_LOANS",
    "CAND_LOAN_REPAY",
    "OTHER_LOAN_REPAY",
    "DEBTS_OWED_BY",
    "TTL_INDIV_CONTRIB",
    "CAND_OFFICE_ST",
    "CAND_OFFICE_DISTRICT",
    "SPEC_ELECTION",
    "PRIM_ELECTION",
    "RUN_ELECTION",
    "GEN_ELECTION",
    "GEN_ELECTION_PRECENT",
    "OTHER_POL_CMTE_CONTRIB",
    "POL_PTY_CONTRIB",
    "CVG_END_DT",
    "INDIV_REFUNDS",
    "CMTE_REFUNDS",
]


def _header(name: str) -> list[str]:
    text = fetch(f"{BULK}/data_dictionaries/{name}_header_file.csv", max_age=30 * 86400).decode()
    return [c.strip() for c in text.strip().split(",")]


def _extract(stem: str, cycle: int):
    yy = f"{cycle % 100:02d}"
    zpath = fetch_to_file(f"{BULK}/{cycle}/{stem}{yy}.zip", CACHE_DIR / "fec" / f"{stem}{yy}.zip")
    out_dir = CACHE_DIR / "fec" / f"{stem}{yy}"
    with zipfile.ZipFile(zpath) as zf:
        members = [m for m in zf.namelist() if m.lower().endswith(".txt")]
        if not out_dir.exists() or any(not (out_dir / m).exists() for m in members):
            zf.extractall(out_dir, members)
    return [out_dir / m for m in members]


def _land_bulk(stem: str, table: str, header_name: str | None) -> int:
    columns = _header(header_name) if header_name else WEBALL_COLUMNS
    paths = []
    for cycle in CYCLES:
        paths.extend(_extract(stem, cycle))
    return db.replace_csv(
        table,
        paths,
        delim="|",
        header=False,
        quote="",
        escape="",
        names=columns,
        union_by_name=False,
        null_padding=True,
        ignore_errors=True,
    )


def _api_aggregates() -> int:
    """Itemized individual receipts per principal campaign committee, by employer / size / state."""
    records = []
    for cand in _mo_candidate_ids():
        info = json.loads(fetch(f"{API}/candidate/{cand}/committees/", {"api_key": FEC_API_KEY, "designation": "P"}))
        for cmte in info.get("results", []):
            for cycle in CYCLES:
                for agg in ("by_employer", "by_size", "by_state"):
                    params = {
                        "api_key": FEC_API_KEY,
                        "committee_id": cmte["committee_id"],
                        "cycle": cycle,
                        "per_page": 100,
                        "sort": "-total",
                    }
                    body = json.loads(fetch(f"{API}/schedules/schedule_a/{agg}/", params))
                    for i, row in enumerate(body.get("results", [])):
                        records.append(
                            (
                                f"{cand}/{cmte['committee_id']}/{cycle}/{agg}/{i}",
                                {"candidate_id": cand, "aggregate": agg, **row},
                            )
                        )
    return db.replace_json("fec_receipt_aggregates", records, source_url=API)


def _mo_candidate_ids() -> list[str]:
    legs = json.loads(fetch("https://unitedstates.github.io/congress-legislators/legislators-current.json"))
    return sorted({fid for p in legs if p["terms"][-1]["state"] == "MO" for fid in p["id"].get("fec", [])})


def _sponsored_committees() -> int:
    """Leadership PACs etc. each member sponsors (not in the bulk files). One call per candidate ID,
    cached for 30 days, so it fits even DEMO_KEY's ~10 calls/hour once the cache is warm."""
    records = []
    for cand in _mo_candidate_ids():
        try:
            body = json.loads(
                fetch(
                    f"{API}/committees/",
                    {"api_key": FEC_API_KEY, "sponsor_candidate_id": cand, "per_page": 100},
                    max_age=30 * 86400,
                )
            )
        except Exception as exc:  # rate limited: keep what we have, report the gap
            print(f"[fec] sponsor lookup for {cand} failed ({exc}); leadership PACs may be incomplete")
            continue
        for row in body.get("results", []):
            records.append((f"{cand}/{row['committee_id']}", {"sponsor_candidate_id": cand, **row}))
    return db.replace_json("fec_sponsored_committees", records, source_url=f"{API}/committees/")


@loader("fec")
def load() -> dict[str, int]:
    counts = {table: _land_bulk(stem, table, hdr) for stem, table, hdr in FILES}
    counts["fec_sponsored_committees"] = _sponsored_committees()
    if os.environ.get("MOGOV_FEC_INDIV") == "1":
        counts["fec_individual_contribs"] = _land_bulk("indiv", "fec_individual_contribs", "indiv")
    if FEC_API_KEY and FEC_API_KEY != "DEMO_KEY":
        counts["fec_receipt_aggregates"] = _api_aggregates()
    else:
        print("[fec] FEC_API_KEY not set: skipping per-member donor aggregates (bulk data still loaded)")
    return counts
