import queue
import threading

import duckdb
import pytest

from mogov import db


@pytest.fixture(autouse=True)
def raw_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    return tmp_path


_CHILD_READY_TIMEOUT_S = 30


def _rows(table: str) -> list[tuple]:
    sql = f"select record_key, payload from read_parquet('{db.raw_glob(table)}') order by 1"
    return duckdb.sql(sql).fetchall()


def test_shards_partition_keys_stably():
    keys = [f"https://example.test/{i}.pdf" for i in range(500)]
    shards = [db.Shard(i, 4) for i in range(4)]
    owned = [s.take(keys) for s in shards]
    assert sorted(k for part in owned for k in part) == sorted(keys)  # every key exactly once
    assert all(owned)  # and spread across all shards
    assert owned == [s.take(reversed(keys))[::-1] for s in shards]  # independent of listing order


def test_invalid_shard_rejected():
    with pytest.raises(ValueError):
        db.Shard(4, 4)


def test_replace_json_streams_a_generator():
    n = db.replace_json("t", ((str(i), {"i": i}) for i in range(3)), source_url="u")
    assert n == 3
    assert _rows("t") == [("0", '{"i": 0}'), ("1", '{"i": 1}'), ("2", '{"i": 2}')]


def test_shards_write_separate_parts_and_replace_their_own():
    for i in range(2):
        db.replace_json("t", [(f"s{i}", {})], shard=db.Shard(i, 2))
    db.replace_json("t", [("s0-again", {})], shard=db.Shard(0, 2))
    assert [k for k, _ in _rows("t")] == ["s0-again", "s1"]


def test_new_shard_count_drops_old_parts(raw_dir):
    for i in range(3):
        db.replace_json("t", [(f"old{i}", {})], shard=db.Shard(i, 3))
    db.replace_json("t", [("new", {})])
    names = sorted(p.name for p in (raw_dir / "t").iterdir())
    assert [n for n in names if n.endswith(".parquet")] == ["part-000-of-001.parquet"]
    assert names == [".part-000-of-001.parquet.lock", "part-000-of-001.parquet"]


def test_new_shard_count_drops_orphan_lock_files_but_not_held_ones(raw_dir):
    folder = db.table_dir("t")
    orphan = folder / f".{db.Shard(0, 3).part_name}.lock"  # a run that failed before publishing: lock, no part
    orphan.write_bytes(b"")
    held_lock = db._ShardLock("t", db.Shard(1, 3))
    held_lock.acquire()  # a live run of the old count
    try:
        db.replace_json("t", [("new", {})])
        assert not orphan.exists()
        assert held_lock.path.exists()
    finally:
        held_lock.release()
    db.replace_json("t", [("new2", {})])  # no longer held: swept on the next publish
    assert sorted(p.name for p in folder.iterdir()) == [".part-000-of-001.parquet.lock", "part-000-of-001.parquet"]


def test_sink_publishes_declared_empty_tables_and_nothing_on_error():
    with db.JsonSink(tables=["a", "b"]) as sink:
        sink.add("a", "k", {"x": 1})
    assert sink.counts == {"a": 1, "b": 0}

    with pytest.raises(RuntimeError), db.JsonSink(tables=["a"]) as sink:
        sink.add("a", "lost", {})
        raise RuntimeError
    assert [k for k, _ in _rows("a")] == ["k"]  # previous landing untouched


def test_replace_csv_without_files_removes_the_shards_part(tmp_path):
    csv = tmp_path / "in.csv"
    csv.write_text("a,b\n1,2\n")
    assert db.replace_csv("c", csv) == 1
    assert db.raw_exists("c")
    assert db.replace_csv("c", []) == 0
    assert not db.raw_exists("c")


def test_legacy_single_file_is_migrated(raw_dir):
    duckdb.sql(f"copy (select 'k' as record_key, '{{}}' as payload) to '{(raw_dir / 'old.parquet').as_posix()}'")
    db.migrate_legacy_layout()
    assert not (raw_dir / "old.parquet").exists()
    assert _rows("old") == [("k", "{}")]


def test_shard_with_nothing_keeps_previous_count_parts(raw_dir):
    db.replace_json("t", [("old", {})])
    db.remove_part("t", db.Shard(1, 2))
    assert [k for k, _ in _rows("t")] == ["old"]
    db.replace_json("t", [("new", {})], shard=db.Shard(0, 2))
    assert [k for k, _ in _rows("t")] == ["new"]


def test_ensure_optional_tables_creates_missing_epa_frs_sic_placeholder():
    # Raw dirs landed before the SIC file joined the EPA FRS loader (#155) must still build.
    assert "epa_frs_sic" in db.ensure_optional_tables()
    assert _rows("epa_frs_sic") == []
    assert "epa_frs_sic" not in db.ensure_optional_tables()  # idempotent; a landed table is left alone


def test_ensure_optional_tables_leaves_landed_rows_alone():
    db.replace_json("epa_frs_sic", [("k1", {"sic": "1"})])
    assert "epa_frs_sic" not in db.ensure_optional_tables()
    assert [k for k, _ in _rows("epa_frs_sic")] == ["k1"]  # the real row survived; no placeholder overwrote it


def test_ensure_optional_tables_creates_typed_mo_house_pdf_placeholders():
    # Builds must work before the mo_house_pdf loader has run (#593): empty tables with the loader's columns.
    created = db.ensure_optional_tables()
    assert {"mo_house_pdf_files", "mo_house_pdf_texts"} <= set(created)
    with db.connect() as con:
        cols = [
            r[0]
            for r in con.execute(
                f"describe select * from read_parquet('{db.raw_glob('mo_house_pdf_texts')}')"
            ).fetchall()
        ]
        n = con.execute(f"select count(*) from read_parquet('{db.raw_glob('mo_house_pdf_texts')}')").fetchone()[0]
    assert {"url", "kind", "page_count", "text", "error"} <= set(cols)
    assert n == 0
    assert "mo_house_pdf_texts" not in db.ensure_optional_tables()


def test_optional_json_tables_map_to_registered_loaders():
    from mogov.loaders import REGISTRY, load_all_modules

    load_all_modules()
    assert set(db.OPTIONAL_JSON_TABLES.values()) | set(db.OPTIONAL_TYPED_TABLES.values()) <= set(REGISTRY)


@pytest.mark.parametrize("sink_type", ["json", "table"])
def test_sink_removes_scratch_files_left_by_killed_runs(raw_dir, sink_type):
    import dataclasses

    @dataclasses.dataclass
    class Row:
        TABLE = "t"
        x: str

    folder = db.table_dir("t")
    part = db.Shard(0, 2).part_name
    mine = [folder / f".{part}.111.jsonl", folder / f".{part}.222.part"]
    other_shard = folder / f".{db.Shard(1, 2).part_name}.333.jsonl"  # another shard's live run: untouched
    published = folder / part
    for path in (*mine, other_shard):
        path.write_text("killed\n")
    shard = db.Shard(0, 2)
    if sink_type == "json":
        with db.JsonSink(shard, tables=["t"]) as sink:
            sink.add("t", "k", {})
    else:
        with db.TableSink(shard, tables=[Row]) as sink:
            sink.add(Row("v"))
    assert sorted(p.name for p in folder.iterdir() if p.suffix != ".lock") == sorted([published.name, other_shard.name])


@pytest.mark.parametrize("sink_type", ["json", "table"])
def test_second_run_of_same_shard_fails_fast_and_leaves_first_run_alone(raw_dir, sink_type):
    import dataclasses

    @dataclasses.dataclass
    class Row:
        TABLE = "t"
        x: str

    def open_sink(shard):
        return db.JsonSink(shard, tables=["t"]) if sink_type == "json" else db.TableSink(shard, tables=[Row])

    def add(sink, v):
        sink.add("t", v, {"v": v}) if sink_type == "json" else sink.add(Row(v))

    with open_sink(db.Shard(0, 2)) as first:
        add(first, "a")
        with pytest.raises(db.ShardBusyError, match="another run is already writing t shard 0 of 2"):
            open_sink(db.Shard(0, 2))
        with open_sink(db.Shard(1, 2)) as other:  # a different shard is not blocked
            add(other, "b")
        add(first, "c")  # first run's scratch file survived the rejected second run
    assert db.table_dir("t").joinpath(db.Shard(0, 2).part_name).exists()
    assert db.table_dir("t").joinpath(db.Shard(1, 2).part_name).exists()
    with open_sink(db.Shard(0, 2)):  # lock released on exit: the shard can run again
        pass


@pytest.fixture
def made_locks(monkeypatch):
    """Every _ShardLock created, kept alive so a test can see whether release() really ran (otherwise
    refcounting closes the file handle and hides a missing release())."""
    made = []
    real_init = db._ShardLock.__init__

    def spy_init(self, *args, **kwargs):
        real_init(self, *args, **kwargs)
        made.append(self)

    monkeypatch.setattr(db._ShardLock, "__init__", spy_init)
    return made


def test_failed_run_releases_the_shard_lock(raw_dir, made_locks):
    with pytest.raises(RuntimeError, match="boom"), db.JsonSink(tables=["t"]):
        raise RuntimeError("boom")
    assert len(made_locks) == 1
    assert made_locks[0]._fh is None
    with db.JsonSink(tables=["t"]):
        pass


def test_partial_open_releases_locks_already_taken(raw_dir, made_locks):
    with db.JsonSink(db.Shard(0, 1), tables=["b"]):
        with pytest.raises(db.ShardBusyError):
            db.JsonSink(db.Shard(0, 1), tables=["a", "b"])
        taken = [lock for lock in made_locks if lock.table == "a"]
        assert len(taken) == 1
        assert taken[0]._fh is None
        with db.JsonSink(db.Shard(0, 1), tables=["a"]):  # "a" was locked then released by the failed open
            pass


def test_killed_holder_leaves_no_stale_lock(raw_dir):
    """A run killed mid-write (no cleanup at all) must not block the next run of its shard."""
    import subprocess
    import sys
    import textwrap

    code = textwrap.dedent(
        """
        import os, sys
        from pathlib import Path
        from mogov import db
        db.RAW_DIR = Path(sys.argv[1])
        sink = db.JsonSink(db.Shard(0, 2), tables=["t"])
        sink.add("t", "k", {"v": 1})
        print("ready", flush=True)
        os._exit(1)  # killed: no __exit__, no unlink, lock file and scratch left behind
        """
    )
    proc = subprocess.run([sys.executable, "-c", code, str(raw_dir)], capture_output=True, text=True, check=False)
    assert "ready" in proc.stdout, proc.stderr
    folder = db.table_dir("t")
    assert list(folder.glob(".*.jsonl")), "the killed run left its scratch file"
    with db.JsonSink(db.Shard(0, 2), tables=["t"]) as sink:
        sink.add("t", "k2", {"v": 2})
    assert [r[0] for r in _rows("t")] == ["k2"]
    assert not list(folder.glob(".*.jsonl"))


def test_second_process_holding_the_shard_makes_this_one_fail_fast(raw_dir):
    """A real cross-process conflict: a child process holds the lock until told to exit."""
    import subprocess
    import sys
    import textwrap

    code = textwrap.dedent(
        """
        import sys
        from pathlib import Path
        from mogov import db
        db.RAW_DIR = Path(sys.argv[1])
        with db.JsonSink(db.Shard(0, 2), tables=["t"]):
            print("ready", flush=True)
            sys.stdin.readline()  # hold the lock until the parent closes stdin
        """
    )
    child = subprocess.Popen(
        [sys.executable, "-c", code, str(raw_dir)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    first_line: queue.Queue[str] = queue.Queue()
    # a blocking readline() has no timeout, so wait for the child's first line from a daemon thread
    threading.Thread(target=lambda: first_line.put(child.stdout.readline()), daemon=True).start()
    try:
        try:
            ready = first_line.get(timeout=_CHILD_READY_TIMEOUT_S)
        except queue.Empty:
            pytest.fail(f"child did not print 'ready' within {_CHILD_READY_TIMEOUT_S}s")
        if ready.strip() != "ready":
            child.kill()
            pytest.fail(f"child did not become ready: {ready!r} {child.communicate()[1]!r}")
        with pytest.raises(db.ShardBusyError, match="another run is already writing t shard 0 of 2"):
            db.JsonSink(db.Shard(0, 2), tables=["t"])
        with db.JsonSink(db.Shard(1, 2), tables=["t"]):  # a different shard is not blocked
            pass
        child.communicate(timeout=30)  # closes the child's stdin, so it exits
    finally:
        if child.poll() is None:  # any failure or timeout above: never leave the child holding the lock
            child.kill()
        child.wait()
        for pipe in (child.stdin, child.stdout, child.stderr):
            pipe.close()
    assert child.returncode == 0
    with db.JsonSink(db.Shard(0, 2), tables=["t"]):  # the child released it on exit
        pass
