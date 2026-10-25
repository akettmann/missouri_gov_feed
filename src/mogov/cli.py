"""`mogov load [source ...]` lands raw data; `mogov build` runs dbt; `mogov run` does everything:
stage-1 loaders -> dbt build -> stage-2 loaders -> dbt build.

Sharding (load and run): `--shards N --shard i` runs shard i of N; `--shards N` alone runs all N shards.
As a Cloud Run job, CLOUD_RUN_TASK_COUNT / CLOUD_RUN_TASK_INDEX supply the defaults, so `--tasks N` on the
job shards the work with no extra flags.

Scheduling: the work is split into jobs of (loaders of one upstream service, shard), run by a process pool
of `--workers` processes. Loaders of different services run at the same time; loaders of one service run
one after another within a shard, so a service sees at most one request stream per shard.
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
import yaml

from mogov import db, obs
from mogov.config import DB_PATH, DBT_DIR, RAW_DIR, ROOT
from mogov.loaders import REGISTRY, SERVICE, SLOW, STAGE, load_all_modules

log = obs.get_logger(__name__)


def _resolve(names: list[str], stage: int | None) -> list[str]:
    load_all_modules()
    for name in names:
        if name not in REGISTRY:
            sys.exit(f"unknown source {name!r}; choose from {', '.join(sorted(REGISTRY))}")
    return names or sorted(n for n in REGISTRY if stage is None or STAGE[n] == stage)


def _run_shard(names: list[str], shard: db.Shard) -> list[str]:
    """Run `names` for one shard, one after another, and return the names that failed (a failure never stops
    the rest)."""

    load_all_modules()
    failed: list[str] = []
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
            failed.append(name)
            obs.loader_failures.add(1, attrs)
            log.exception("loader.failed")
        finally:
            elapsed = time.perf_counter() - started
            obs.loader_duration.record(elapsed, attrs)
            log.info("loader.finished", seconds=round(elapsed, 1))
            structlog.contextvars.unbind_contextvars(*attrs)
    obs.flush()
    return failed


def _jobs(names: list[str], shards: int, indexes) -> list[tuple[list[str], db.Shard]]:
    """(loaders of one service, shard) jobs in start order: every shard's slow services first, so none of
    them is left as the tail of the run; within a tier shard-major, so the first wave spreads over services
    instead of putting every shard on one service."""
    groups: dict[str, list[str]] = {}
    for name in names:
        groups.setdefault(SERVICE[name], []).append(name)
    jobs = [(group, db.Shard(i, shards)) for i in indexes for group in groups.values()]
    return sorted(jobs, key=lambda job: not SLOW.intersection(job[0]))  # stable: keeps shard-major order


def default_workers(shards: int) -> int:
    return max(shards, min(os.cpu_count() or 1, 8))


def _summarize(results: list[list[str]]) -> list[str]:
    failed = sorted({name for r in results for name in r})
    if failed:
        log.error("loader.summary", failed=failed, hint="these loaders failed; their raw data is stale")
    return failed


def run_loaders(
    names: list[str],
    stage: int | None = None,
    *,
    shards: int = 1,
    shard: int | None = None,
    workers: int | None = None,
) -> list[str]:
    """Run every selected loader even if some fail; return the sorted names of the loaders that failed
    (empty when all succeeded)."""

    names = _resolve(names, stage)
    db.migrate_legacy_layout()
    jobs = _jobs(names, shards, [shard] if shard is not None else range(shards))
    workers = min(len(jobs), workers or default_workers(shards))
    if workers <= 1:
        results = [_run_shard(group, s) for group, s in jobs]
        return _summarize(results)
    log.info("loader.pool", shards=shards, workers=workers, jobs=len(jobs))
    # spawn, not fork: workers must not inherit the parent's HTTP client or DuckDB handles
    with ProcessPoolExecutor(workers, mp_context=multiprocessing.get_context("spawn")) as pool:
        futures = [pool.submit(_run_shard, group, s) for group, s in jobs]
        return _summarize([f.result() for f in futures])


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
        help="run only this shard (0-based; default: $CLOUD_RUN_TASK_INDEX). Omit to run every shard.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=int(os.environ["MOGOV_WORKERS"]) if os.environ.get("MOGOV_WORKERS") else None,
        help="processes running loader jobs at once (default: $MOGOV_WORKERS, else max(shards, min(CPUs, 8)))",
    )


def _gate_build(failed: list[str], allowed: list[str]) -> bool:
    """True when it is OK to run dbt after a loader pass. Strict by default: any failed loader blocks the build.
    A failed loader named in `allowed` (--allow-failed-loader) is tolerated with a stale-data warning."""

    blocking = [n for n in failed if n not in allowed]
    for name in failed:
        if name in allowed:
            log.warning(
                "build.stale_source", source=name, hint=f"{name} failed to load; building on its stale raw data"
            )
    if blocking:
        log.error(
            "build.skipped",
            failed=blocking,
            hint="fix them, or allow one: --allow-failed-loader NAME or MOGOV_ALLOW_FAILED_LOADERS=NAME",
        )
    return not blocking


def _allowed_failed(flag_values: list[str]) -> list[str]:
    """Sources whose failure may not stop `run`: --allow-failed-loader flags plus $MOGOV_ALLOW_FAILED_LOADERS
    (comma-separated; for runtimes with fixed args such as compose or Cloud Run). Unknown names are rejected."""

    env = [n.strip() for n in os.environ.get("MOGOV_ALLOW_FAILED_LOADERS", "").split(",") if n.strip()]
    names = [*flag_values, *env]
    _resolve(names, None)  # reject unknown names up front
    return names


def _on_sigterm(signum, _frame):
    # Cloud Run stops tasks with SIGTERM; exit through Python so finally blocks drop temp files and metrics flush.
    log.warning("process.terminated", signal=signum)
    sys.exit(128 + signum)


def _merge_user_vars(args: list[str], dbt_vars: dict) -> tuple[list[str], dict]:
    """Fold any user `--vars <yaml>` / `--vars=<yaml>` in `args` into `dbt_vars` (user keys win).

    dbt parses --vars as YAML (JSON is a subset) and warns or drops one of two flags, so mogov must pass one.
    Returns the args without the user's flag and the merged vars; exits with a clear error if it is malformed.
    """

    rest, merged, i = [], dict(dbt_vars), 0
    while i < len(args):
        arg = args[i]
        if arg == "--vars" or arg.startswith("--vars="):
            if arg == "--vars":
                if i + 1 >= len(args):
                    sys.exit("mogov: --vars needs a YAML/JSON mapping value")
                raw, i = args[i + 1], i + 2
            else:
                raw, i = arg.removeprefix("--vars="), i + 1
            try:
                user = yaml.safe_load(raw)
            except yaml.YAMLError as exc:
                sys.exit(f"mogov: could not parse --vars {raw!r} as YAML/JSON: {exc}")
            if user is None:
                user = {}
            if not isinstance(user, dict):
                sys.exit(f"mogov: --vars must be a YAML/JSON mapping, got {raw!r}")
            merged.update(user)
        else:
            rest.append(arg)
            i += 1
    return rest, merged


def run_dbt(args: list[str]) -> int:
    for table in db.ensure_optional_tables():
        log.warning("dbt.placeholder", table=f"raw.{table}", reason="not loaded yet; using an empty placeholder")
    # Models over opt-in CSV sources (no empty placeholder possible) are switched on when the data exists.
    dbt_vars = {"mec_direct": db.raw_exists("mec_cd1_a"), "cl_case_bulk": db.raw_exists("cl_mo_opinion_clusters")}
    args, dbt_vars = _merge_user_vars(args, dbt_vars)
    dirs = ["--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    env = {**os.environ, "MOGOV_DB": str(DB_PATH), "MOGOV_RAW_DIR": RAW_DIR.as_posix()}
    # dbt's console-script entry point. Not `-m dbt.cli.main`: the dbt.cli package imports that module first, so
    # runpy warns it "found in sys.modules ... prior to execution".
    dbt = [sys.executable, "-c", "from dbt.cli.main import cli; cli()"]
    if not (DBT_DIR / "dbt_packages" / "dbt_utils").exists():  # packages.yml (pinned by package-lock.yml)
        subprocess.check_call([*dbt, "deps", *dirs], cwd=ROOT, env=env)
    # Every subcommand mogov uses accepts --vars, and dbt 1.11 also runs the on-run-start hook for
    # `source freshness` (which reads the vars), so always pass them.
    cmd = [*dbt, *args, *dirs, "--vars", json.dumps(dbt_vars)]
    return subprocess.call(cmd, cwd=ROOT, env=env)


def export(fmt: str) -> None:
    """Copy every marts and reporting table to data/exports/<table>.<fmt> (csv or parquet)."""

    out = DB_PATH.parent / "exports"
    out.mkdir(parents=True, exist_ok=True)
    with db.connect(str(DB_PATH), read_only=True) as con:
        tables = con.execute(
            "select table_schema, table_name from information_schema.tables "
            "where table_schema in ('marts', 'reporting') order by 2"
        ).fetchall()
        for schema, t in tables:
            dest = (out / f"{t}.{fmt}").as_posix()
            opts = "(format csv, header true)" if fmt == "csv" else "(format parquet, compression zstd)"
            con.execute(f"copy {schema}.{t} to '{dest}' {opts}")
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
    p_export = sub.add_parser("export", help="write marts and reporting tables to data/exports/")
    p_export.add_argument("--format", choices=["csv", "parquet"], default="parquet")
    p_run = sub.add_parser("run", help="load everything, then dbt build")
    p_run.add_argument("sources", nargs="*")
    _shard_args(p_run)
    p_run.add_argument(
        "--allow-failed-loader",
        action="append",
        default=[],
        metavar="SOURCE",
        help="if this loader fails, still run dbt build on its stale raw data (warned by name; repeatable). "
        "By default any failed loader stops the run before dbt. The exit code is non-zero either way. "
        "Also read from $MOGOV_ALLOW_FAILED_LOADERS (comma-separated), for runtimes with fixed args.",
    )
    args, extra = parser.parse_known_args()
    if extra and args.cmd != "build":
        parser.error(f"unrecognized arguments: {' '.join(extra)}")

    if args.cmd == "list":
        load_all_modules()
        print("\n".join(f"{n}  (stage {STAGE[n]}, service {SERVICE[n]})" for n in sorted(REGISTRY)))
    elif args.cmd == "load":
        failed = run_loaders(args.sources, shards=args.shards, shard=args.shard, workers=args.workers)
        sys.exit(1 if failed else 0)
    elif args.cmd == "export":
        export(args.format)
    elif args.cmd == "build":
        sys.exit(run_dbt(["build", *extra]))
    elif args.cmd == "freshness":
        sys.exit(run_dbt(["source", "freshness"]))
    elif args.cmd == "run":
        allowed = _allowed_failed(args.allow_failed_loader)
        shards = {"shards": args.shards, "shard": args.shard, "workers": args.workers}
        failed = run_loaders(args.sources, stage=1, **shards)
        if not _gate_build(failed, allowed):
            sys.exit(1)
        rc = run_dbt(["build"])
        if not args.sources:
            stage2 = run_loaders([], stage=2, **shards)
            failed += stage2
            if not _gate_build(stage2, allowed):
                sys.exit(1)
            rc = run_dbt(["build"]) or rc
        sys.exit(rc or (1 if failed else 0))


if __name__ == "__main__":
    try:
        main()
    finally:
        obs.shutdown()
