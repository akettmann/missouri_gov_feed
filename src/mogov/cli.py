"""`mogov load [source ...]` lands raw data; `mogov build` runs dbt; `mogov run` does everything:
stage-1 loaders -> dbt build -> stage-2 loaders -> dbt build."""

import argparse
import json
import os
import subprocess
import sys
import time

from mogov import db, obs
from mogov.config import DB_PATH, DBT_DIR, RAW_DIR, ROOT
from mogov.loaders import REGISTRY, STAGE, load_all_modules

log = obs.get_logger(__name__)


def run_loaders(names: list[str], stage: int | None = None) -> bool:
    load_all_modules()
    names = names or sorted(n for n in REGISTRY if stage is None or STAGE[n] == stage)
    ok = True
    for name in names:
        if name not in REGISTRY:
            sys.exit(f"unknown source {name!r}; choose from {', '.join(sorted(REGISTRY))}")
        log.info("loader.start", loader=name)
        started = time.perf_counter()
        try:
            for table, n in REGISTRY[name]().items():
                log.info("loader.landed", loader=name, table=f"raw.{table}", rows=n)
                obs.rows_landed.add(n, {"loader": name, "table": table})
        except Exception:  # one broken upstream shouldn't stop the others
            ok = False
            obs.loader_failures.add(1, {"loader": name})
            log.exception("loader.failed", loader=name)
        finally:
            obs.loader_duration.record(time.perf_counter() - started, {"loader": name})
    return ok


def run_dbt(args: list[str]) -> int:
    for table in db.ensure_optional_tables():
        log.warning("dbt.placeholder", table=f"raw.{table}", reason="not loaded yet; using an empty placeholder")
    # Models over opt-in CSV sources (no empty placeholder possible) are switched on when the data exists.
    dbt_vars = {"mec_direct": db.raw_path("mec_cd1_a").exists()}
    cmd = [sys.executable, "-m", "dbt.cli.main", *args, "--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    if args and args[0] in ("build", "run", "test", "compile", "seed"):
        cmd += ["--vars", json.dumps(dbt_vars)]
    return subprocess.call(
        cmd, cwd=ROOT, env={**os.environ, "MOGOV_DB": str(DB_PATH), "MOGOV_RAW_DIR": RAW_DIR.as_posix()}
    )


def export(fmt: str) -> None:
    """Copy every marts table to data/exports/<table>.<fmt> (csv or parquet)."""
    import duckdb

    out = DB_PATH.parent / "exports"
    out.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        tables = [
            r[0]
            for r in con.execute(
                "select table_name from information_schema.tables where table_schema = 'marts' order by 1"
            ).fetchall()
        ]
        for t in tables:
            dest = (out / f"{t}.{fmt}").as_posix()
            opts = "(format csv, header true)" if fmt == "csv" else "(format parquet, compression zstd)"
            con.execute(f"copy marts.{t} to '{dest}' {opts}")
            log.info("export.written", path=dest)


def main() -> None:
    import atexit

    atexit.register(obs.shutdown)
    parser = argparse.ArgumentParser(prog="mogov")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_load = sub.add_parser("load", help="run loaders (all if none given)")
    p_load.add_argument("sources", nargs="*")
    sub.add_parser("list", help="list loaders")
    sub.add_parser("build", help="dbt build; extra arguments pass through to dbt (e.g. -s +fct_votes)")
    p_export = sub.add_parser("export", help="write marts tables to data/exports/")
    p_export.add_argument("--format", choices=["csv", "parquet"], default="csv")
    p_run = sub.add_parser("run", help="load everything, then dbt build")
    p_run.add_argument("sources", nargs="*")
    args, extra = parser.parse_known_args()
    if extra and args.cmd != "build":
        parser.error(f"unrecognized arguments: {' '.join(extra)}")

    if args.cmd == "list":
        load_all_modules()
        print("\n".join(f"{n}  (stage {STAGE[n]})" for n in sorted(REGISTRY)))
    elif args.cmd == "load":
        sys.exit(0 if run_loaders(args.sources) else 1)
    elif args.cmd == "export":
        export(args.format)
    elif args.cmd == "build":
        sys.exit(run_dbt(["build", *extra]))
    elif args.cmd == "run":
        loaded = run_loaders(args.sources, stage=1)
        rc = run_dbt(["build"])
        if not args.sources:
            loaded = run_loaders([], stage=2) and loaded
            rc = run_dbt(["build"]) or rc
        sys.exit(rc or (0 if loaded else 1))


if __name__ == "__main__":
    try:
        main()
    finally:
        obs.shutdown()
