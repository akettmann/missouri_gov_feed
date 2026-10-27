"""Build the site twice and fail if the two outputs differ (the site must be byte-identical on tied rows, #226).

    uv run python scripts/check_site_determinism.py [--shuffle] [--exports DIR]

Builds `frontend/` into two temp directories and compares every file by SHA-256. With --shuffle the second build
reads a copy of the exports whose rows were put in random order, so any `order by`, `row_number()` or sort that
ends on a tie shows up as a difference even when the engine happens to read tied rows the same way twice.
Reads the exports read-only (default `data/exports`, or --exports / MOGOV_EXPORTS); needs `pnpm install` in
`frontend/`. Run it occasionally (and after touching a ranking), not on every commit: a build takes minutes.
It needs the real local exports, so it has no CI job (#459); schedule it locally, see docs/environment.md. The
compare and shuffle logic is covered in CI by tests/test_site_determinism.py.
Exits 1 on any difference and lists the first few differing files.
"""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]


def _shuffled_copy(src: Path, dst: Path, seed: float | None = None) -> None:
    con = duckdb.connect()
    if seed is not None:
        con.execute(f"select setseed({float(seed)})")
    for f in sorted(src.glob("*.parquet")):
        src_file = f.as_posix().replace("'", "''")
        dst_file = (dst / f.name).as_posix().replace("'", "''")
        con.execute(
            f"copy (select * from read_parquet('{src_file}') order by random()) to '{dst_file}' (format parquet)"
        )
    con.close()


def _build(exports: Path, out: Path) -> None:
    env = {**os.environ, "MOGOV_EXPORTS": str(exports)}
    cmd = ["pnpm", "exec", "astro", "build", "--outDir", str(out)]
    subprocess.run(cmd, cwd=ROOT / "frontend", env=env, check=True, shell=os.name == "nt")


def _hashes(root: Path) -> dict[str, str]:
    return {
        p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(root.rglob("*"))
        if p.is_file()
    }


def find_differences(
    exports: Path,
    tmp_dir: Path,
    *,
    shuffle: bool,
    seed: float | None = None,
    build: Callable[[Path, Path], None] = _build,
) -> tuple[list[str], int]:
    """Build twice into tmp_dir/a and tmp_dir/b; return (differing relative paths, file count).

    `build` is injectable so tests/test_site_determinism.py can prove a tie is caught without running astro."""
    second_exports = exports
    if shuffle:
        second_exports = tmp_dir / "shuffled_exports"
        second_exports.mkdir()
        _shuffled_copy(exports, second_exports, seed)
    build(exports, tmp_dir / "a")
    build(second_exports, tmp_dir / "b")
    a, b = _hashes(tmp_dir / "a"), _hashes(tmp_dir / "b")
    shutil.rmtree(tmp_dir / "a", ignore_errors=True)
    shutil.rmtree(tmp_dir / "b", ignore_errors=True)
    return sorted(k for k in a.keys() | b.keys() if a.get(k) != b.get(k)), len(a | b)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--shuffle", action="store_true", help="build the second time from exports with shuffled rows")
    ap.add_argument("--exports", type=Path, default=Path(os.environ.get("MOGOV_EXPORTS", ROOT / "data" / "exports")))
    args = ap.parse_args()
    if not args.exports.is_dir() or not any(args.exports.glob("*.parquet")):
        sys.exit(f"no exports (*.parquet) in {args.exports}; run `mogov export` first, or pass --exports DIR")
    if not (args.exports / "dim_official.parquet").exists():
        sys.exit(
            f"{args.exports} is missing dim_official.parquet (a partial or incomplete export); re-run `mogov export`"
        )
    with tempfile.TemporaryDirectory(prefix="mogov_det_") as tmp:
        diff, total = find_differences(args.exports, Path(tmp), shuffle=args.shuffle)
    if diff:
        print(f"{len(diff)} of {total} files differ between the two builds, e.g.:")
        for k in diff[:20]:
            print("  ", k)
        return 1
    print(f"identical: {total} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
