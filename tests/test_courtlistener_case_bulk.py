import bz2
import csv

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
