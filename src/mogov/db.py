"""Landing helpers. Loaders only land data, verbatim, as Parquet under RAW_DIR/<table>/.

Each raw table is a directory of part files, one per shard: part-<shard>-of-<shards>.parquet (an unsharded
run writes part-000-of-001). dbt reads `<table>/*.parquet` as one source (see dbt/models/staging/_sources.yml)
and does all the shaping. Landing to files rather than the warehouse keeps loaders independent of DuckDB's
single-writer lock, so several loaders, shards and a dbt build can run at once.

Writes are atomic per part file (written as .part, then renamed), so re-running a shard simply replaces its
own part. A shard that writes a part also deletes parts left by runs with a different shard count; when
changing the shard count, run every shard before the next dbt build.
"""

import contextlib
import json
import os
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from zlib import crc32

import duckdb

from mogov.config import RAW_DIR


@dataclass(frozen=True)
class Shard:
    """This process's slice of a loader's work. Work units are assigned by a stable hash of their key, so
    the split doesn't depend on listing order or on which other shards are running."""

    index: int = 0
    count: int = 1

    def __post_init__(self):
        if not (self.count >= 1 and 0 <= self.index < self.count):
            raise ValueError(f"invalid shard {self.index} of {self.count}")

    def owns(self, key: str) -> bool:
        return self.count == 1 or crc32(key.encode()) % self.count == self.index

    def take[T](self, items: Iterable[T], key=str) -> list[T]:
        return [item for item in items if self.owns(key(item))]

    @property
    def part_name(self) -> str:
        return f"part-{self.index:03d}-of-{self.count:03d}.parquet"


UNSHARDED = Shard()


def connect(database: str = ":memory:", **kwargs) -> duckdb.DuckDBPyConnection:
    """duckdb.connect without the terminal progress bar DuckDB draws for queries over ~2s, which lands in the
    middle of the structured logs. It's a session setting, so it can't go in connect()'s config."""
    con = duckdb.connect(database, **kwargs)
    con.execute("set enable_progress_bar = false")
    return con


def _connect() -> duckdb.DuckDBPyConnection:
    # Streaming copy: don't hold whole files in memory to preserve row order.
    return connect(
        config={
            "preserve_insertion_order": False,
            "memory_limit": os.environ.get("MOGOV_DUCKDB_MEMORY", "3GB"),
            "threads": int(os.environ.get("MOGOV_DUCKDB_THREADS", "4")),
        }
    )


def table_dir(table: str) -> Path:
    path = RAW_DIR / table
    path.mkdir(parents=True, exist_ok=True)
    legacy = RAW_DIR / f"{table}.parquet"  # pre-sharding layout: one file per table
    if legacy.exists() and not any(path.glob("*.parquet")):
        with contextlib.suppress(FileNotFoundError):  # another process moved it first
            legacy.replace(path / UNSHARDED.part_name)
    return path


def raw_glob(table: str) -> str:
    """read_parquet() argument covering every part of a raw table."""
    return (table_dir(table) / "*.parquet").as_posix()


def raw_exists(table: str) -> bool:
    return any(table_dir(table).glob("*.parquet"))


def migrate_legacy_layout() -> None:
    for legacy in RAW_DIR.glob("*.parquet"):
        table_dir(legacy.stem)


def _publish(con: duckdb.DuckDBPyConnection, select_sql: str, table: str, shard: Shard, params=None) -> int:
    folder = table_dir(table)
    dest = folder / shard.part_name
    tmp = folder / f".{shard.part_name}.{os.getpid()}.part"
    try:
        con.execute(f"copy ({select_sql}) to '{tmp.as_posix()}' (format parquet, compression zstd)", params or [])
        tmp.replace(dest)
    finally:
        tmp.unlink(missing_ok=True)
    _drop_other_shard_counts(folder, shard)
    return con.execute(f"select count(*) from read_parquet('{dest.as_posix()}')").fetchone()[0]


def _drop_other_shard_counts(folder: Path, shard: Shard) -> None:
    for old in folder.glob("part-*-of-*.parquet"):
        if not old.name.endswith(f"-of-{shard.count:03d}.parquet"):
            old.unlink(missing_ok=True)


def remove_part(table: str, shard: Shard = UNSHARDED) -> None:
    """This shard has nothing for <table> (e.g. it owns none of its files): drop any part it wrote before.
    Parts from a previous shard count stay until the shard that now owns the data replaces them, so the
    table is never left empty mid-run."""
    (table_dir(table) / shard.part_name).unlink(missing_ok=True)


class JsonSink:
    """Streams (record_key, payload) rows for one or more raw JSON tables to disk as they're produced, then
    publishes each table's part on a clean exit. On an exception nothing is published, so a failed run
    leaves the previous landing in place.

        with db.JsonSink(shard, source_url=BASE) as sink:
            sink.add("mo_house_bills", key, payload)
        sink.counts  # {"mo_house_bills": 1234}

    Tables named in `tables` are published even when empty, so a shard that owns no rows for a table
    still replaces its stale part.
    """

    def __init__(self, shard: Shard = UNSHARDED, *, source_url: str | None = None, tables: Iterable[str] = ()):
        self.shard, self.source_url = shard, source_url
        self.counts: dict[str, int] = {}
        self._files: dict[str, tuple[Path, object]] = {}
        for table in tables:
            self._file(table)

    def _file(self, table: str):
        if table not in self._files:
            path = table_dir(table) / f".{self.shard.part_name}.{os.getpid()}.jsonl"
            self._files[table] = (path, path.open("w", encoding="utf-8"))
        return self._files[table][1]

    def add(self, table: str, key: str, payload: object, *, source_url: str | None = None) -> None:
        line = {
            "record_key": key,
            "payload": json.dumps(payload, default=str),
            "source_url": source_url or self.source_url,
        }
        self._file(table).write(json.dumps(line) + "\n")

    def extend(self, table: str, records: Iterable[tuple[str, object]]) -> None:
        for key, payload in records:
            self.add(table, key, payload)

    def __enter__(self) -> "JsonSink":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        try:
            for fh in (fh for _, fh in self._files.values()):
                fh.close()
            if exc_type is None:
                loaded_at = datetime.now(UTC)
                with _connect() as con:
                    for table, (path, _) in self._files.items():
                        self.counts[table] = _publish(con, _jsonl_select(path), table, self.shard, [loaded_at])
        finally:
            for path, _ in self._files.values():
                path.unlink(missing_ok=True)


def _jsonl_select(path: Path) -> str:
    return (
        "select record_key, payload, source_url, ?::timestamptz as loaded_at "
        f"from read_json('{path.as_posix()}', format = 'newline_delimited', "
        "columns = {record_key: 'varchar', payload: 'varchar', source_url: 'varchar'}, "
        "maximum_object_size = 67108864)"  # largest payload today is ~0.6 MB
    )


def replace_json(
    table: str, records: Iterable[tuple[str, object]], *, source_url: str | None = None, shard: Shard = UNSHARDED
) -> int:
    """Replace this shard's part of raw <table> with (record_key, payload JSON text, source_url, loaded_at)
    rows. `records` is consumed lazily, so a generator keeps memory flat."""
    with JsonSink(shard, source_url=source_url, tables=[table]) as sink:
        sink.extend(table, records)
    return sink.counts[table]


def replace_csv(table: str, path: Path | list[Path], *, shard: Shard = UNSHARDED, **read_opts) -> int:
    """Replace this shard's part of raw <table> with the verbatim contents of CSV file(s), all columns as
    text. With no files (the shard owns none of them) its part is removed instead."""
    paths = [Path(p).as_posix() for p in (path if isinstance(path, list) else [path])]
    if not paths:
        remove_part(table, shard)
        return 0
    opts = {"all_varchar": True, "header": True, "union_by_name": True, "filename": True, **read_opts}
    opt_sql = ", ".join(f"{k} = {_sql_literal(v)}" for k, v in opts.items())
    with _connect() as con:
        return _publish(con, f"select * from read_csv({_sql_literal(paths)}, {opt_sql})", table, shard)


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
    "epa_frs_sic",  # added to the EPA FRS loader after the first landings (#123); older raw dirs lack it
    # RSMo statutes (#34): a first load takes hours (the site allows ~1 request/s), so builds run without it
    "mo_revisor_chapters",
    "mo_revisor_sections",
    "mo_revisor_repeals",
]


def ensure_optional_tables() -> list[str]:
    created = []
    for table in OPTIONAL_JSON_TABLES:
        if not raw_exists(table):
            replace_json(table, [])
            created.append(table)
    return created
