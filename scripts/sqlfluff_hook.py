"""Run sqlfluff for pre-commit, installing dbt packages first when a fresh checkout lacks them.

    python scripts/sqlfluff_hook.py fix --force <files>
    python scripts/sqlfluff_hook.py lint <files>

The dbt templater compiles the project, which fails with UninstalledPackagesFoundError until
`dbt deps` has populated the gitignored dbt/dbt_packages/. Linting itself uses the in-memory `lint`
target (dbt/profiles.yml), so no data/ directory is needed.
"""

import subprocess
import sys
from pathlib import Path

DBT_DIR = Path(__file__).resolve().parent.parent / "dbt"


def main() -> int:
    if not (DBT_DIR / "dbt_packages").is_dir():
        deps = subprocess.run(
            ["dbt", "deps", "--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR), "--target", "lint"],
            check=False,
        )
        if deps.returncode:
            return deps.returncode
    return subprocess.run(["sqlfluff", *sys.argv[1:]], check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
