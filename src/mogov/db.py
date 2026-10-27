"""Landing helpers. Loaders only land data, verbatim, as Parquet under RAW_DIR/<table>/.

Each raw table is a directory of part files, one per shard: part-<shard>-of-<shards>.parquet (an unsharded
run writes part-000-of-001). dbt reads `<table>/*.parquet` as one source (see dbt/models/staging/_sources.yml)
and does all the shaping. Landing to files rather than the warehouse keeps loaders independent of DuckDB's
single-writer lock, so several loaders, shards and a dbt build can run at once.

Writes are atomic per part file (written as .part, then renamed), so re-running a shard simply replaces its
own part. When the shard count changes, the old count's parts are deleted only once every shard of the new
count has landed (see _drop_other_shard_counts); until then dbt would read both, so run every shard before the
next dbt build.
"""

import contextlib
import dataclasses
import errno
import json
import os
import sys
import typing
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from zlib import crc32

import duckdb
import structlog

from mogov.config import RAW_DIR
from mogov.http import tmp_sibling

log = structlog.get_logger()


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


def own_rows_sql(table: str, keys: Iterable[str], recency: str = "landed_at", *, union_by_name: bool = False) -> str:
    """A `select` over a raw table that a loader reads back to learn its own state, tolerating two shard counts
    coexisting (a shard-count change leaves the old parts until the new count has fully landed, see
    `_drop_other_shard_counts`). Keeps one row per `keys`: the latest by `recency`, ties broken by the part file
    name, which is unique, so the choice is deterministic. `recency` is any expression; rows where it is NULL rank
    oldest. `union_by_name` reads parts whose columns differ (columns added since an older landing are NULL).
    The part name is read into a private column (`_own_part`), not DuckDB's default `filename`, so a table that
    has its own `filename` column (every `replace_csv` table does) comes back intact."""
    cols = ", ".join(keys)
    by_name = "union_by_name = true, " if union_by_name else ""
    return (
        f"select * exclude (_own_rn, _own_part) from (select *, row_number() over ("
        f"partition by {cols} order by {recency} desc nulls last, _own_part desc) as _own_rn "
        f"from read_parquet('{raw_glob(table)}', {by_name}filename = '_own_part')) where _own_rn = 1"
    )


def raw_exists(table: str) -> bool:
    return any(table_dir(table).glob("*.parquet"))


def migrate_legacy_layout() -> None:
    for legacy in RAW_DIR.glob("*.parquet"):
        table_dir(legacy.stem)


def _publish(con: duckdb.DuckDBPyConnection, select_sql: str, table: str, shard: Shard, params=None) -> int:
    folder = table_dir(table)
    dest = folder / shard.part_name
    tmp = tmp_sibling(dest)
    try:
        con.execute(f"copy ({select_sql}) to '{tmp.as_posix()}' (format parquet, compression zstd)", params or [])
        tmp.replace(dest)
    finally:
        tmp.unlink(missing_ok=True)
    _none_marker(folder, shard).unlink(missing_ok=True)
    _drop_other_shard_counts(folder, shard)
    return con.execute(f"select count(*) from read_parquet('{dest.as_posix()}')").fetchone()[0]


class ShardBusyError(RuntimeError):
    """Another run is already writing this (table, shard)."""


class _ShardLock:
    """Exclusive OS lock on `<table>/.<part>.lock`, held for a sink's life, so a second run of the same shard
    fails fast instead of deleting the first run's scratch files. The OS drops the lock when the process
    exits (even killed), so a crash never leaves a stale lock; the lock file itself is left in place (deleting
    it would race with a waiting run) and is harmless: dbt reads only `*.parquet`.

    The lock is local to the filesystem the raw dir is on (one machine, or a filesystem with working
    flock/fcntl locks). If the filesystem can't lock at all (some network or FUSE mounts), it logs a warning
    and carries on unlocked rather than blocking the load."""

    def __init__(self, table: str, shard: Shard):
        self.table, self.shard = table, shard
        self.path = table_dir(table) / f".{shard.part_name}.lock"
        self._fh = None

    def acquire(self) -> None:
        fh = self.path.open("ab")
        try:
            _lock_fd(fh.fileno())
        except BlockingIOError:
            fh.close()
            raise ShardBusyError(
                f"another run is already writing {self.table} shard {self.shard.index} of {self.shard.count} "
                f"(lock held on {self.path}); wait for it to finish, or run a different shard"
            ) from None
        except OSError as e:
            log.warning("shard_lock_unsupported", path=str(self.path), error=str(e))
            fh.close()
            return
        self._fh = fh

    def release(self) -> None:
        if self._fh is not None:
            try:
                _unlock_fd(self._fh.fileno())
            finally:
                self._fh.close()
                self._fh = None


if sys.platform == "win32":
    import msvcrt

    def _lock_fd(fd: int) -> None:
        try:
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
        except OSError as e:
            if e.errno in (errno.EACCES, errno.EDEADLK):  # held by another handle
                raise BlockingIOError from e
            raise

    def _unlock_fd(fd: int) -> None:
        msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)

else:
    import fcntl

    def _lock_fd(fd: int) -> None:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)  # raises BlockingIOError when held

    def _unlock_fd(fd: int) -> None:
        fcntl.flock(fd, fcntl.LOCK_UN)


def _scratch_path(table: str, shard: Shard) -> Path:
    """A fresh JSONL scratch file for a sink. Named like http.tmp_sibling (pid + uuid): the pid alone is not
    unique across containers sharing a directory. `_clear_stale_scratch` matches it by the `.<part>.` prefix."""
    return tmp_sibling(table_dir(table) / shard.part_name).with_suffix(".jsonl")


def _clear_stale_scratch(table: str, shard: Shard) -> None:
    """Delete this shard's scratch files for <table> left by runs that were killed before they could clean up
    (they are named .<part>.<pid>.<uuid>.jsonl / .part, so each is one dead run's). A shard is a single
    writer, and a killed run's rows are never wanted, so starting a sink for the shard makes them stale."""
    folder = table_dir(table)
    # a run that starts and then crashes must count as "not landed", not as the empty shard an old marker says
    _none_marker(folder, shard).unlink(missing_ok=True)
    for suffix in ("jsonl", "part"):
        for stale in folder.glob(f".{shard.part_name}.*.{suffix}"):
            stale.unlink(missing_ok=True)


def _unlink_lock_if_free(lock_path: Path) -> None:
    """Delete an old shard count's lock file, unless a live run still holds it. Held is detected with a
    non-blocking lock (on POSIX unlinking a held file succeeds and would let a later run lock a fresh file
    alongside the live one; on Windows the unlink would fail anyway). Closing before unlinking leaves a tiny
    window; overlapping shard counts are unsupported, so that is accepted."""
    try:
        fh = lock_path.open("r+b")  # never creates: a lock file that is already gone needs nothing
    except OSError:
        return
    try:
        try:
            _lock_fd(fh.fileno())
        except OSError:  # held by a live run (or the filesystem can't lock): leave the file alone
            log.debug("shard_lock_file_kept", path=str(lock_path))
            return
        _unlock_fd(fh.fileno())
    finally:
        fh.close()
    with contextlib.suppress(OSError):
        lock_path.unlink(missing_ok=True)


def _none_marker(folder: Path, shard: Shard) -> Path:
    return folder / f".{shard.part_name}.none"


def _count_is_complete(folder: Path, count: int) -> bool:
    """Every shard of a `count`-way split has landed: it has a part, or a `.none` marker saying it owns no data."""
    return all(
        (folder / Shard(i, count).part_name).exists() or _none_marker(folder, Shard(i, count)).exists()
        for i in range(count)
    )


def _drop_other_shard_counts(folder: Path, shard: Shard) -> None:
    """Remove parts, `.none` markers and lock files written under a different shard count, but only once
    every shard of this shard's count has landed.

    Cloud Run tasks start in waves, so the first new-count shard to publish must not delete old-count parts:
    loaders that read their own previous parts (mo_house_pdf.previous_files) would lose history for shards that
    start later. Until the new count is complete the old parts stay, so a reader of `*.parquet` sees both
    counts (rows twice); as before, run every shard before the next dbt build. If the transition never
    completes, the next run of any complete count (including the old one) sweeps the leftovers. Idempotent:
    shards finishing together may both sweep. A lock file is removed even when its part never got published
    (a run that failed first leaves only the lock), if no run holds it."""
    if not _count_is_complete(folder, shard.count):
        return
    suffix = f"-of-{shard.count:03d}.parquet"
    for old in folder.glob("part-*-of-*.parquet"):
        if not old.name.endswith(suffix):
            old.unlink(missing_ok=True)
    for marker in folder.glob(".part-*-of-*.parquet.none"):
        if not marker.name.endswith(f"{suffix}.none"):
            marker.unlink(missing_ok=True)
    for lock_path in folder.glob(".part-*-of-*.parquet.lock"):
        if not lock_path.name.endswith(f"{suffix}.lock"):
            _unlink_lock_if_free(lock_path)


@contextlib.contextmanager
def _shard_locked(table: str, shard: Shard) -> Iterator[None]:
    """Hold the (table, shard) lock for a one-shot write (remove_part, replace_csv), as a sink does for its life.
    The lock is non-blocking, so it can never deadlock: a second holder, even in the same process (flock locks
    belong to the open file, not the process), fails at once with ShardBusyError. Callers must not nest it with
    a sink on the same (table, shard)."""
    lock = _ShardLock(table, shard)
    lock.acquire()
    try:
        yield
    finally:
        lock.release()


def remove_part(table: str, shard: Shard = UNSHARDED) -> None:
    """This shard has nothing for <table> (e.g. it owns none of its files): drop any part it wrote before.
    Parts from a previous shard count stay until every shard of the new count has landed (this one is recorded
    with a `.none` marker, so owning nothing doesn't stall that), so the table is never left empty mid-run."""
    folder = table_dir(table)
    with _shard_locked(table, shard):
        (folder / shard.part_name).unlink(missing_ok=True)
        _none_marker(folder, shard).write_bytes(b"")
    _drop_other_shard_counts(folder, shard)


def _lock_shard(locks: dict[str, _ShardLock], table: str, shard: Shard) -> None:
    lock = _ShardLock(table, shard)
    lock.acquire()
    locks[table] = lock


def _close_sink(files: dict, locks: dict) -> None:
    """Close scratch files, delete them, then release the shard locks (scratch is gone before another run
    may start)."""
    try:
        for path, fh in files.values():
            fh.close()
            path.unlink(missing_ok=True)
    finally:
        for lock in locks.values():
            lock.release()
        locks.clear()


class JsonSink:
    """Streams (record_key, payload) rows for one or more raw JSON tables to disk as they're produced, then
    publishes each table's part on a clean exit. On an exception nothing is published, so a failed run
    leaves the previous landing in place.

        with db.JsonSink(shard, source_url=BASE) as sink:
            sink.add("senate_bills", key, payload)
        sink.counts  # {"senate_bills": 1234}

    Tables named in `tables` are published even when empty, so a shard that owns no rows for a table
    still replaces its stale part.
    """

    def __init__(self, shard: Shard = UNSHARDED, *, source_url: str | None = None, tables: Iterable[str] = ()):
        self.shard, self.source_url = shard, source_url
        self.counts: dict[str, int] = {}
        self._files: dict[str, tuple[Path, object]] = {}
        self._locks: dict[str, _ShardLock] = {}
        try:
            for table in tables:
                self._file(table)
        except BaseException:
            self._close()
            raise

    def _file(self, table: str):
        if table not in self._files:
            _lock_shard(self._locks, table, self.shard)
            _clear_stale_scratch(table, self.shard)
            path = _scratch_path(table, self.shard)
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

    def _close(self) -> None:
        _close_sink(self._files, self._locks)

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
            self._close()


_DUCKDB_TYPES = {str: "varchar", int: "bigint", float: "double", bool: "boolean", date: "date", datetime: "timestamptz"}


def _column_type(annotation) -> str:
    """DuckDB type for a row field annotated `T` or `T | None` (T one of str, int, float, bool, date, datetime)."""
    args = [a for a in typing.get_args(annotation) if a is not type(None)]
    return _DUCKDB_TYPES[args[0] if args else annotation]


def row_columns(row_type: type) -> dict[str, str]:
    hints = typing.get_type_hints(row_type)
    return {f.name: _column_type(hints[f.name]) for f in dataclasses.fields(row_type)}


class TableSink:
    """Streams statically typed rows (dataclass instances) to disk as they're produced, then publishes one
    typed raw table per row class on a clean exit. Each row class names its table in a `TABLE` class attribute
    and declares its columns as annotated fields (`str`, `int`, `float`, `bool`, `date`, `datetime`, each
    optionally `| None`). Row classes named in `tables` are published even when empty. On an exception nothing
    is published, so a failed run leaves the previous landing in place.
    """

    def __init__(self, shard: Shard = UNSHARDED, *, tables: Iterable[type] = ()):
        self.shard = shard
        self.counts: dict[str, int] = {}
        self._types: dict[str, type] = {}
        self._files: dict[str, tuple[Path, object]] = {}
        self._locks: dict[str, _ShardLock] = {}
        try:
            for row_type in tables:
                self._file(row_type)
        except BaseException:
            self._close()
            raise

    def _file(self, row_type: type):
        table = row_type.TABLE
        if table not in self._files:
            _lock_shard(self._locks, table, self.shard)
            _clear_stale_scratch(table, self.shard)
            path = _scratch_path(table, self.shard)
            self._types[table] = row_type
            self._files[table] = (path, path.open("w", encoding="utf-8"))
        return self._files[table][1]

    def add(self, row) -> None:
        self._file(type(row)).write(json.dumps(dataclasses.asdict(row), default=str) + "\n")

    def _close(self) -> None:
        _close_sink(self._files, self._locks)

    def __enter__(self) -> "TableSink":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        try:
            for fh in (fh for _, fh in self._files.values()):
                fh.close()
            if exc_type is None:
                loaded_at = datetime.now(UTC)
                with _connect() as con:
                    for table, (path, _) in self._files.items():
                        cols = row_columns(self._types[table])
                        spec = ", ".join(f"{name}: '{typ}'" for name, typ in cols.items())
                        select = (
                            f"select {', '.join(cols)}, ?::timestamptz as loaded_at "
                            f"from read_json('{path.as_posix()}', format = 'newline_delimited', columns = {{{spec}}}, "
                            "maximum_object_size = 67108864)"
                        )
                        self.counts[table] = _publish(con, select, table, self.shard, [loaded_at])
        finally:
            self._close()


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
    with _shard_locked(table, shard), _connect() as con:  # fail fast if a sink or another run is writing this shard
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


# Raw JSON tables that may legitimately be absent: stage-2, opt-in or key-gated loaders, or tables added to a
# loader after earlier landings. dbt models read them unconditionally, so empty placeholders are created before
# a build when they're missing. Maps each table to the loader that writes it (the one to run to fill it); a test
# checks every value is a registered loader.
OPTIONAL_JSON_TABLES = {
    "cl_cases": "courtlistener_cases",
    "senate_efd_filings": "senate_efd",
    "senate_efd_rows": "senate_efd",
    "fec_receipt_aggregates": "fec",
    "fec_sponsored_committees": "fec",
    "wikidata_positions": "wikidata",
    "wikidata_attributes": "wikidata",
    "wikidata_relatives": "wikidata",
    "wikidata_own_leadership": "wikidata",
    "wikidata_mo_officeholders": "wikidata",
    "mo_sos_election_rows": "mo_sos_elections",  # new source (#287); older raw dirs lack it
    "mo_state_expenditures": "mo_state_expenditures",
    "epa_frs_sic": "epa_frs",  # added to the EPA FRS loader after the first landings (#123); older raw dirs lack it
    "mo_auditor_reports": "mo_auditor",  # a loader that has not run yet in this environment (#288)
    "mo_auditor_ratings": "mo_auditor",
    "mo_revisor_chapters": "mo_revisor",  # RSMo statutes (#34): a first load takes hours, so builds run without it
    "mo_revisor_sections": "mo_revisor",
    "mo_revisor_repeals": "mo_revisor",
    "epa_frs_alt_names": "epa_frs",  # added for U+FFFD name repair (#260); older raw dirs lack it
    "mo_senate_bill_list": "mo_senate_bills",  # a slow loader (~1 request/s per bill, #585): builds run without it
    "mo_senate_bill_actions": "mo_senate_bills",
    "govinfo_billstatus_files": "govinfo_billstatus",  # new source (#283): older raw dirs lack it
    "govinfo_billstatus_bills": "govinfo_billstatus",
    "govinfo_billstatus_sponsors": "govinfo_billstatus",
    "govinfo_billstatus_cosponsors": "govinfo_billstatus",
    "govinfo_billstatus_actions": "govinfo_billstatus",
    "govinfo_billstatus_recorded_votes": "govinfo_billstatus",
    "govinfo_billstatus_laws": "govinfo_billstatus",
}


# Optional typed tables (written by TableSink from row dataclasses): table -> loader. dbt reads these too, so a
# missing one gets an empty table with the row class's columns. The row classes are found by importing the loader
# lazily (db is imported by the loaders).
OPTIONAL_TYPED_TABLES = {
    "mo_house_pdf_files": "mo_house_pdf",  # stage 2 and ~19 hours for a first full run (#591); builds run without it
    "mo_house_pdf_texts": "mo_house_pdf",
    "mo_house_pdf_statute_refs": "mo_house_pdf",  # #594
}


def _typed_placeholder(table: str) -> None:
    import importlib

    module = importlib.import_module(f"mogov.loaders.{OPTIONAL_TYPED_TABLES[table]}")
    row_types = [v for v in vars(module).values() if isinstance(v, type) and getattr(v, "TABLE", None) == table]
    with TableSink(tables=row_types):
        pass  # a clean exit publishes the empty typed table


def ensure_optional_tables() -> list[str]:
    created = []
    for table in OPTIONAL_JSON_TABLES:
        if not raw_exists(table):
            replace_json(table, [])
            created.append(table)
    for table in OPTIONAL_TYPED_TABLES:
        if not raw_exists(table):
            _typed_placeholder(table)
            created.append(table)
    return created
