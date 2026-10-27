"""scripts/check_site_determinism.py catches a tie that sorts differently when the input row order changes (#459).

The real check builds the whole site from the local exports, which CI does not have, so CI exercises the compare and
shuffle logic with a tiny stand-in "build" that ranks fixed rows.
"""

import importlib.util
from pathlib import Path

import duckdb

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "check_site_determinism.py"
spec = importlib.util.spec_from_file_location("check_site_determinism", SCRIPT)
det = importlib.util.module_from_spec(spec)
spec.loader.exec_module(det)

# Many tied scores: with 50 rows all at 1, a "top 1 by score" that ends on the tie picks whichever row comes first.
ROWS = [(f"o{i:02d}", 1) for i in range(50)]


def _exports(tmp_path: Path) -> Path:
    d = tmp_path / "exports"
    d.mkdir()
    duckdb.connect().execute(
        f"copy (select * from (values {','.join(str(r) for r in ROWS)}) t(name, score)) "
        f"to '{(d / 'dim_official.parquet').as_posix()}' (format parquet)"
    )
    return d


def _fake_build(order_by: str):
    def build(exports: Path, out: Path) -> None:
        out.mkdir(parents=True)
        top = (
            duckdb.connect()
            .execute(
                f"select name from read_parquet('{(exports / 'dim_official.parquet').as_posix()}') "
                f"order by {order_by} limit 1"
            )
            .fetchone()[0]
        )
        (out / "index.html").write_text(top, encoding="utf-8")

    return build


def test_tied_sort_is_flagged_under_shuffle(tmp_path):
    (tmp_path / "w1").mkdir()
    diff, total = det.find_differences(
        _exports(tmp_path), tmp_path / "w1", shuffle=True, seed=0.5, build=_fake_build("score desc")
    )
    assert diff == ["index.html"]
    assert total == 1


def test_total_order_passes_under_shuffle(tmp_path):
    (tmp_path / "w2").mkdir()
    diff, _ = det.find_differences(
        _exports(tmp_path), tmp_path / "w2", shuffle=True, seed=0.5, build=_fake_build("score desc, name")
    )
    assert diff == []
