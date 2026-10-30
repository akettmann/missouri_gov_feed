r"""Case history from CourtListener's quarterly bulk exports: dockets, opinion clusters and opinion panels in
Missouri state and federal courts. Replaces most of the REST API case search, whose token is capped at
~125 requests/day. Trade-off: several GB per quarter, and cases up to three months stale (the API loader,
courtlistener_cases, still tops up recent ones).

The national files are far too big to land whole (dockets alone are ~5 GB compressed), so this loader
filters while it streams. That is its only change to the data: kept records are copied byte for byte.
  dockets                       court_id in MO_COURTS
  opinion-clusters              docket_id in the kept dockets
  search_opinioncluster_panel   opinioncluster_id in the kept clusters
DuckDB can't read bz2, so records are split in Python. The export is Postgres CSV with ESCAPE '\': a quote
inside a field is written \" (not doubled), so a record ends at a newline once its running count of
unescaped quotes is even.

The filtered CSVs are cached per snapshot, so only a new quarterly snapshot means re-reading the files.
One work unit (each file depends on the previous one), so a single shard does it all.
"""

import bz2
import csv
import io
import re
from collections.abc import Iterator
from pathlib import Path

from mogov import db, obs
from mogov.config import CACHE_DIR
from mogov.http import fetch_to_file, replace_file, sweep_stale_parts, tmp_sibling
from mogov.loaders import loader
from mogov.loaders.courtlistener_bulk import BUCKET, _latest_snapshot

log = obs.get_logger(__name__)

MO_COURTS = ["mo", "moctapp", "moctapped", "moctappwd", "moctappsd", "moed", "mowd", "ca8"]
CACHE = CACHE_DIR / "courtlistener"
CSV_DIALECT = {"escapechar": "\\", "doublequote": False}
_ESCAPED = re.compile(r"\\.", re.S)  # a backslash and the character it escapes
csv.field_size_limit(2**31 - 1)  # opinion headmatter runs to megabytes (C long limit on Windows)
TABLES = {
    "dockets": "cl_mo_dockets",
    "opinion-clusters": "cl_mo_opinion_clusters",
    "search_opinioncluster_panel": "cl_mo_cluster_panel",
}


def _records(path: Path, phase: str) -> Iterator[str]:
    """Raw CSV records (newlines inside quoted fields kept), header first."""
    size = path.stat().st_size
    progress = obs.Progress(f"{phase} (compressed MiB read)", size >> 20, log)
    with path.open("rb") as raw, bz2.BZ2File(raw) as unzipped:
        text = io.TextIOWrapper(unzipped, encoding="utf-8", errors="surrogateescape", newline="")
        parts: list[str] = []
        quotes, last_mib = 0, 0
        for line in text:
            parts.append(line)
            quotes += (_ESCAPED.sub("", line) if "\\" in line else line).count('"')
            if quotes % 2 == 0:
                yield "".join(parts)
                parts.clear()
                quotes = 0
                mib = raw.tell() >> 20
                if mib != last_mib:
                    progress.tick(mib - last_mib)
                    last_mib = mib
        if parts:
            yield "".join(parts)
    progress.finish()


def _parse(record: str) -> list[str]:
    return next(csv.reader([record], **CSV_DIALECT))


def _filter(stem: str, snap: str, column: str, keep: set[str], prefilter=None) -> tuple[Path, set[str]]:
    """Copy the records whose `column` is in `keep` to a cached CSV; returns it and the kept records' ids."""
    out = CACHE / f"mo-{stem}-{snap}.csv"
    ids_path = out.with_suffix(".ids")
    if out.exists() and ids_path.exists():
        return out, set(ids_path.read_text().split())
    src = fetch_to_file(f"{BUCKET}/bulk-data/{stem}-{snap}.csv.bz2", CACHE / f"{stem}-{snap}.csv.bz2", max_age=None)
    sweep_stale_parts(out)
    tmp = tmp_sibling(out)
    ids: set[str] = set()
    records = _records(src, stem)
    header = next(records)
    columns = _parse(header)
    key_at, id_at = columns.index(column), columns.index("id")
    try:
        with tmp.open("w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            fh.write(header)
            for record in records:
                if prefilter and not prefilter(record):
                    continue
                row = _parse(record)
                if row[key_at] in keep:
                    fh.write(record)
                    ids.add(row[id_at])
        replace_file(tmp, out)
    finally:
        tmp.unlink(missing_ok=True)
    ids_path.write_text("\n".join(sorted(ids)))
    log.info("cl_bulk.filtered", file=stem, kept=len(ids))
    return out, ids


@loader("courtlistener_case_bulk", service="courtlistener-s3", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """One unit: the snapshot."""
    if not shard.owns("courtlistener_case_bulk"):
        return {table: db.replace_csv(table, [], shard=shard) for table in TABLES.values()}
    snap = _latest_snapshot()
    quoted_courts = [f'"{c}"' for c in MO_COURTS]
    # Cheap substring test first: few dockets mention a Missouri court id at all.
    dockets, docket_ids = _filter(
        "dockets", snap, "court_id", set(MO_COURTS), prefilter=lambda r: any(c in r for c in quoted_courts)
    )
    clusters, cluster_ids = _filter("opinion-clusters", snap, "docket_id", docket_ids)
    panel, _ = _filter("search_opinioncluster_panel", snap, "opinioncluster_id", cluster_ids)
    opts = {"escape": "\\", "strict_mode": False, "parallel": False, "shard": shard}
    return {
        "cl_mo_dockets": db.replace_csv("cl_mo_dockets", dockets, **opts),
        "cl_mo_opinion_clusters": db.replace_csv("cl_mo_opinion_clusters", clusters, **opts),
        "cl_mo_cluster_panel": db.replace_csv("cl_mo_cluster_panel", panel, **opts),
    }
