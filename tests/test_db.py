import duckdb
import pytest

from mogov import db


@pytest.fixture(autouse=True)
def raw_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    return tmp_path


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
    assert sorted(p.name for p in (raw_dir / "t").iterdir()) == ["part-000-of-001.parquet"]


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
