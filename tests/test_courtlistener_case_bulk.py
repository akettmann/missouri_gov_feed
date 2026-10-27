import bz2
import csv

import pytest

from mogov.loaders.courtlistener_case_bulk import CSV_DIALECT, _parse, _records

# Postgres COPY ... CSV ESCAPE '\': quotes inside fields are backslash-escaped, so a field can hold an odd
# number of quote characters.
ROWS = [
    ["id", "court_id", "text"],
    ["1", "mo", "plain"],
    ["2", "txctapp14", 'a 5" pipe'],
    ["3", "ca8", 'spans\nseveral\r\nlines, "quoted", with a comma'],
    ["4", "mowd", "back\\slash"],
    ["5", "", ""],
]


def test_records_split_postgres_csv_without_changing_bytes(tmp_path):
    path = tmp_path / "x.csv.bz2"
    with bz2.open(path, "wt", encoding="utf-8", newline="") as fh:
        csv.writer(fh, quoting=csv.QUOTE_ALL, lineterminator="\n", **CSV_DIALECT).writerows(ROWS)
    original = bz2.decompress(path.read_bytes()).decode()
    assert '\\"' in original  # the fixture really uses backslash escapes

    records = list(_records(path, "test"))

    assert "".join(records) == original  # kept records are byte-for-byte copies
    assert [_parse(r) for r in records] == ROWS


def _setup_filter(tmp_path, monkeypatch, records):
    from mogov.loaders import courtlistener_case_bulk as m

    monkeypatch.setattr(m, "CACHE", tmp_path)
    src = tmp_path / "src.csv.bz2"
    src.write_bytes(b"")
    monkeypatch.setattr(m, "fetch_to_file", lambda *a, **k: src)
    monkeypatch.setattr(m, "_records", records)
    return m


def test_filter_uses_unique_tmp_names_and_cleans_up_on_failure(tmp_path, monkeypatch):
    seen = []

    def boom(src, stem):
        yield "id,court_id\n"
        seen.extend(p.name for p in tmp_path.glob("*.part"))
        raise RuntimeError("download died")

    m = _setup_filter(tmp_path, monkeypatch, boom)
    with pytest.raises(RuntimeError):
        m._filter("dockets", "2025", "court_id", {"mo"})
    assert len(seen) == 1 and seen[0].startswith(".")  # a temp file existed mid-run, under a hidden unique name
    assert list(tmp_path.glob("*.part")) == []  # failed run removed its own temp file


def test_filter_tmp_names_differ_between_concurrent_runs(tmp_path, monkeypatch):
    names = []

    def records(src, stem):
        yield "id,court_id\n"
        yield "1,mo\n"
        names.extend(p.name for p in tmp_path.glob(".*.part"))

    m = _setup_filter(tmp_path, monkeypatch, records)
    m._filter("dockets", "2025", "court_id", {"mo"})
    (tmp_path / "mo-dockets-2025.csv").unlink()
    (tmp_path / "mo-dockets-2025.ids").unlink()
    m._filter("dockets", "2025", "court_id", {"mo"})
    assert len(names) == 2 and names[0] != names[1]
    assert (tmp_path / "mo-dockets-2025.csv").read_text() == "id,court_id\n1,mo\n"
