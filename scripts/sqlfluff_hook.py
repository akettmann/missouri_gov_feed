"""Run sqlfluff for pre-commit, installing dbt packages first when they are missing or stale.

    python scripts/sqlfluff_hook.py fix --force <files>
    python scripts/sqlfluff_hook.py lint <files>

The dbt templater compiles the project, which fails with UninstalledPackagesFoundError until
`dbt deps` has populated the gitignored dbt/dbt_packages/. Packages count as stale when
dbt_packages/ is missing, any package named in package-lock.yml has no directory there, or
packages.yml / package-lock.yml changed since the last successful `dbt deps` run here (tracked by
a hash marker inside dbt_packages/). The common up-to-date case does no dbt invocation.
sqlfluff is run through a small wrapper (`--run-sqlfluff`) that raises Python's recursion limit and
stack size: the nested committee_names macros in int_mec__donor_committees.sql parse deeper than the
default 1000 frames (#70). sqlfluff reports a file it could not process ("due to an internal error",
e.g. a RecursionError) as a WARNING and still exits 0, so the hook scans the output for that and fails.
Linting itself uses the in-memory `lint` target (dbt/profiles.yml), so no data/ directory is needed.
"""

import hashlib
import os
import re
import subprocess
import sys
import threading
from pathlib import Path

DBT_DIR = Path(__file__).resolve().parent.parent / "dbt"
MARKER_NAME = ".deps_hash"
RECURSION_LIMIT = 20000
STACK_BYTES = 64 * 1024 * 1024
# Phrases sqlfluff prints (exit code still 0) when it gave up on a file without linting it.
_INTERNAL_ERROR_RE = re.compile(r"due to an internal error|Traceback \(most recent call last\)")
_NAME_RE = re.compile(r"^\s*-?\s*name:\s*['\"]?([^\s'\"]+)", re.MULTILINE)


def locked_package_names(lock_file: Path) -> list[str]:
    """Return the package names recorded in package-lock.yml (empty if absent)."""
    if not lock_file.is_file():
        return []
    return _NAME_RE.findall(lock_file.read_text(encoding="utf-8"))


def deps_fingerprint(dbt_dir: Path) -> str:
    """Hash of packages.yml and package-lock.yml contents."""
    digest = hashlib.sha256()
    for name in ("packages.yml", "package-lock.yml"):
        path = dbt_dir / name
        digest.update(path.read_bytes() if path.is_file() else b"")
        digest.update(b"\0")
    return digest.hexdigest()


def packages_stale(dbt_dir: Path) -> bool:
    """True when `dbt deps` needs to run for dbt_dir."""
    packages_dir = dbt_dir / "dbt_packages"
    if not packages_dir.is_dir():
        return True
    if any(not (packages_dir / name).is_dir() for name in locked_package_names(dbt_dir / "package-lock.yml")):
        return True
    marker = packages_dir / MARKER_NAME
    return not marker.is_file() or marker.read_text(encoding="utf-8").strip() != deps_fingerprint(dbt_dir)


def run_deps(dbt_dir: Path) -> int:
    """Run `dbt deps`; record the fingerprint on success."""
    deps = subprocess.run(
        ["dbt", "deps", "--project-dir", str(dbt_dir), "--profiles-dir", str(dbt_dir), "--target", "lint"],
        check=False,
    )
    if deps.returncode == 0:
        packages_dir = dbt_dir / "dbt_packages"
        packages_dir.mkdir(exist_ok=True)
        (packages_dir / MARKER_NAME).write_text(deps_fingerprint(dbt_dir), encoding="utf-8")
    return deps.returncode


def has_internal_error(output: str) -> bool:
    """True when sqlfluff output says it could not process a file (it still exits 0 in that case)."""
    return _INTERNAL_ERROR_RE.search(output) is not None


def run_sqlfluff_inprocess(args: list[str]) -> int:
    """Run the sqlfluff CLI in a big-stack thread with a raised recursion limit; return its exit code."""
    from sqlfluff.cli.commands import cli

    sys.setrecursionlimit(RECURSION_LIMIT)
    threading.stack_size(STACK_BYTES)
    result: list[int] = [1]

    def target() -> None:
        try:
            cli.main(args=args, prog_name="sqlfluff", standalone_mode=False)
            result[0] = 0
        except SystemExit as exc:
            result[0] = exc.code if isinstance(exc.code, int) else int(bool(exc.code))

    thread = threading.Thread(target=target)
    thread.start()
    thread.join()
    return result[0]


def _echo(data: bytes) -> None:
    """Write the child's UTF-8 bytes to stdout without depending on the console's encoding."""
    buffer = getattr(sys.stdout, "buffer", None)
    if buffer is not None:
        sys.stdout.flush()
        buffer.write(data)
        buffer.flush()
    else:
        sys.stdout.write(data.decode("utf-8", errors="replace"))


def run_sqlfluff(args: list[str]) -> int:
    """Run sqlfluff via the wrapper, echoing its output; non-zero if it exits non-zero or hit an internal error."""
    # Force UTF-8 in the child so its pipe output does not use the locale encoding (cp1252 on Windows).
    proc = subprocess.run(
        [sys.executable, "-X", "utf8", str(Path(__file__).resolve()), "--run-sqlfluff", *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    _echo(proc.stdout)
    if has_internal_error(proc.stdout.decode("utf-8", errors="replace")):
        sys.stderr.write("sqlfluff_hook: sqlfluff hit an internal error on a file (see above); failing.\n")
        return proc.returncode or 1
    return proc.returncode


def main() -> int:
    if sys.argv[1:2] == ["--run-sqlfluff"]:
        return run_sqlfluff_inprocess(sys.argv[2:])
    if packages_stale(DBT_DIR):
        code = run_deps(DBT_DIR)
        if code:
            return code
    return run_sqlfluff(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
