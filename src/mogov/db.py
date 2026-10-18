"""Landing helpers. Loaders only land data, verbatim, as one Parquet file per raw table under RAW_DIR.

dbt reads those files as sources (see dbt/models/staging/_sources.yml) and does all the shaping.
Landing to files rather than the warehouse keeps loaders independent of DuckDB's single-writer lock,
so several loaders and a dbt build can run at once.
"""

import json
from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path

import duckdb

from mogov.config import RAW_DIR


def _connect() -> duckdb.DuckDBPyConnection:
    # Streaming copy: don't hold whole files in memory to preserve row order.
    return duckdb.connect(config={"preserve_insertion_order": False, "memory_limit": "3GB", "threads": 4})


def raw_path(table: str) -> Path:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    return RAW_DIR / f"{table}.parquet"


def _write(con: duckdb.DuckDBPyConnection, select_sql: str, table: str, params: list | None = None) -> int:
    dest = raw_path(table)
    tmp = dest.with_suffix(".parquet.part")
    con.execute(f"copy ({select_sql}) to '{tmp.as_posix()}' (format parquet, compression zstd)", params or [])
    tmp.replace(dest)
    return con.execute(f"select count(*) from read_parquet('{dest.as_posix()}')").fetchone()[0]


def replace_json(table: str, records: Iterable[tuple[str, object]], *, source_url: str | None = None) -> int:
    """Replace raw <table> with (record_key, payload JSON text, source_url, loaded_at) rows."""
    loaded_at = datetime.now(UTC)
    rows = [(key, json.dumps(payload, default=str), source_url, loaded_at) for key, payload in records]
    with _connect() as con:
        con.execute("create table t (record_key varchar, payload varchar, source_url varchar, loaded_at timestamptz)")
        if rows:
            con.executemany("insert into t values (?, ?, ?, ?)", rows)
        return _write(con, "select * from t", table)


def replace_csv(table: str, path: Path | list[Path], **read_opts) -> int:
    """Replace raw <table> with the verbatim contents of CSV file(s), all columns as text."""
    paths = [Path(p).as_posix() for p in (path if isinstance(path, list) else [path])]
    opts = {"all_varchar": True, "header": True, "union_by_name": True, "filename": True, **read_opts}
    opt_sql = ", ".join(f"{k} = {_sql_literal(v)}" for k, v in opts.items())
    with _connect() as con:
        return _write(con, f"select * from read_csv({_sql_literal(paths)}, {opt_sql})", table)


def _sql_literal(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(_sql_literal(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{_sql_literal(k)}: {_sql_literal(x)}" for k, x in v.items()) + "}"
    return "'" + str(v).replace("'", "''") + "'"


# Raw JSON tables that may legitimately be absent: stage-2, opt-in or key-gated loaders. dbt models
# read them unconditionally, so empty placeholders are created before a build when they're missing.
OPTIONAL_JSON_TABLES = [
    "cl_cases",
    "senate_efd_filings",
    "senate_efd_rows",
    "fec_receipt_aggregates",
    "fec_sponsored_committees",
    "wikidata_positions",
    "wikidata_attributes",
    "wikidata_relatives",
    "wikidata_own_leadership",
    "wikidata_mo_officeholders",
]


def ensure_optional_tables() -> list[str]:
    created = []
    for table in OPTIONAL_JSON_TABLES:
        if not raw_path(table).exists():
            replace_json(table, [])
            created.append(table)
    return created
