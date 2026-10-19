"""`mogov load [source ...]` lands raw data; `mogov build` runs dbt; `mogov run` does everything:
stage-1 loaders -> dbt build -> stage-2 loaders -> dbt build.

Sharding (load and run): `--shards N --shard i` runs shard i of N in this process; `--shards N` alone runs
all N shards in a process pool. As a Cloud Run job, CLOUD_RUN_TASK_COUNT / CLOUD_RUN_TASK_INDEX supply
the defaults, so `--tasks N` on the job shards the work with no extra flags.
"""

import argparse
import json
import multiprocessing
import os
import signal
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import structlog

from mogov import db, obs
from mogov.config import DB_PATH, DBT_DIR, RAW_DIR, ROOT
from mogov.loaders import REGISTRY, STAGE, load_all_modules

log = obs.get_logger(__name__)


def _resolve(names: list[str], stage: int | None) -> list[str]:
    load_all_modules()
    for name in names:
        if name not in REGISTRY:
            sys.exit(f"unknown source {name!r}; choose from {', '.join(sorted(REGISTRY))}")
    return names or sorted(n for n in REGISTRY if stage is None or STAGE[n] == stage)


def _run_shard(names: list[str], shard: db.Shard) -> bool:
    load_all_modules()
    ok = True
    for name in names:
        attrs = {"loader": name, "shard": f"{shard.index}/{shard.count}"}
        structlog.contextvars.bind_contextvars(**attrs)
        log.info("loader.start")
        started = time.perf_counter()
        try:
            for table, n in REGISTRY[name](shard).items():
                log.info("loader.landed", table=f"raw.{table}", rows=n)
                obs.rows_landed.add(n, {**attrs, "table": table})
        except Exception:  # one broken upstream shouldn't stop the others
            ok = False
            obs.loader_failures.add(1, attrs)
            log.exception("loader.failed")
        finally:
            elapsed = time.perf_counter() - started
            obs.loader_duration.record(elapsed, attrs)
            log.info("loader.finished", seconds=round(elapsed, 1))
            structlog.contextvars.unbind_contextvars(*attrs)
    obs.flush()
    return ok


def run_loaders(names: list[str], stage: int | None = None, *, shards: int = 1, shard: int | None = None) -> bool:
    names = _resolve(names, stage)
    db.migrate_legacy_layout()
    if shard is not None or shards == 1:
        return _run_shard(names, db.Shard(shard or 0, shards))
    log.info("loader.pool", shards=shards)
    # spawn, not fork: workers must not inherit the parent's HTTP client or DuckDB handles
    with ProcessPoolExecutor(shards, mp_context=multiprocessing.get_context("spawn")) as pool:
        futures = [pool.submit(_run_shard, names, db.Shard(i, shards)) for i in range(shards)]
        return all(f.result() for f in futures)


def _shard_args(parser: argparse.ArgumentParser) -> None:
    env_count, env_index = os.environ.get("CLOUD_RUN_TASK_COUNT"), os.environ.get("CLOUD_RUN_TASK_INDEX")
    parser.add_argument(
        "--shards",
        type=int,
        default=int(env_count or 1),
        help="split each loader's work into this many shards (default: $CLOUD_RUN_TASK_COUNT or 1)",
    )
    parser.add_argument(
        "--shard",
        type=int,
        default=int(env_index) if env_index is not None else None,
        help="run only this shard (0-based; default: $CLOUD_RUN_TASK_INDEX). Omit to run every shard in a pool.",
    )


def _on_sigterm(signum, _frame):
    # Cloud Run stops tasks with SIGTERM; exit through Python so finally blocks drop temp files and metrics flush.
    log.warning("process.terminated", signal=signum)
    sys.exit(128 + signum)


def run_dbt(args: list[str]) -> int:
    for table in db.ensure_optional_tables():
        log.warning("dbt.placeholder", table=f"raw.{table}", reason="not loaded yet; using an empty placeholder")
    # Models over opt-in CSV sources (no empty placeholder possible) are switched on when the data exists.
    dbt_vars = {"mec_direct": db.raw_exists("mec_cd1_a"), "cl_case_bulk": db.raw_exists("cl_mo_opinion_clusters")}
    dirs = ["--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    env = {**os.environ, "MOGOV_DB": str(DB_PATH), "MOGOV_RAW_DIR": RAW_DIR.as_posix()}
    if not (DBT_DIR / "dbt_packages" / "dbt_utils").exists():  # packages.yml (pinned by package-lock.yml)
        subprocess.check_call([sys.executable, "-m", "dbt.cli.main", "deps", *dirs], cwd=ROOT, env=env)
    cmd = [sys.executable, "-m", "dbt.cli.main", *args, *dirs]
    if args and args[0] in ("build", "run", "test", "compile", "seed"):
        cmd += ["--vars", json.dumps(dbt_vars)]
    return subprocess.call(cmd, cwd=ROOT, env=env)


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
    signal.signal(signal.SIGTERM, _on_sigterm)
    parser = argparse.ArgumentParser(prog="mogov")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_load = sub.add_parser("load", help="run loaders (all if none given)")
    p_load.add_argument("sources", nargs="*")
    _shard_args(p_load)
    sub.add_parser("list", help="list loaders")
    sub.add_parser("build", help="dbt build; extra arguments pass through to dbt (e.g. -s +fct_votes)")
    sub.add_parser("freshness", help="how long since each always-on loader last landed data (dbt source freshness)")
    p_export = sub.add_parser("export", help="write marts tables to data/exports/")
    p_export.add_argument("--format", choices=["csv", "parquet"], default="csv")
    p_run = sub.add_parser("run", help="load everything, then dbt build")
    p_run.add_argument("sources", nargs="*")
    _shard_args(p_run)
    args, extra = parser.parse_known_args()
    if extra and args.cmd != "build":
        parser.error(f"unrecognized arguments: {' '.join(extra)}")

    if args.cmd == "list":
        load_all_modules()
        print("\n".join(f"{n}  (stage {STAGE[n]})" for n in sorted(REGISTRY)))
    elif args.cmd == "load":
        sys.exit(0 if run_loaders(args.sources, shards=args.shards, shard=args.shard) else 1)
    elif args.cmd == "export":
        export(args.format)
    elif args.cmd == "build":
        sys.exit(run_dbt(["build", *extra]))
    elif args.cmd == "freshness":
        sys.exit(run_dbt(["source", "freshness"]))
    elif args.cmd == "run":
        shards = {"shards": args.shards, "shard": args.shard}
        loaded = run_loaders(args.sources, stage=1, **shards)
        rc = run_dbt(["build"])
        if not args.sources:
            loaded = run_loaders([], stage=2, **shards) and loaded
            rc = run_dbt(["build"]) or rc
        sys.exit(rc or (0 if loaded else 1))


if __name__ == "__main__":
    try:
        main()
    finally:
        obs.shutdown()
