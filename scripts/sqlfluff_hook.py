"""Run sqlfluff for pre-commit, installing dbt packages first when they are missing or stale.

    python scripts/sqlfluff_hook.py fix --force <files>
    python scripts/sqlfluff_hook.py lint <files>

The dbt templater compiles the project, which fails with UninstalledPackagesFoundError until
`dbt deps` has populated the gitignored dbt/dbt_packages/. Packages count as stale when
dbt_packages/ is missing, any package named in package-lock.yml has no directory there, or
packages.yml / package-lock.yml changed since the last successful `dbt deps` run here (tracked by
a hash marker inside dbt_packages/). The common up-to-date case does no dbt invocation.
Linting itself uses the in-memory `lint` target (dbt/profiles.yml), so no data/ directory is needed.
"""

import hashlib
import re
import subprocess
import sys
from pathlib import Path

DBT_DIR = Path(__file__).resolve().parent.parent / "dbt"
MARKER_NAME = ".deps_hash"
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


def main() -> int:
    if packages_stale(DBT_DIR):
        code = run_deps(DBT_DIR)
        if code:
            return code
    return subprocess.run(["sqlfluff", *sys.argv[1:]], check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
