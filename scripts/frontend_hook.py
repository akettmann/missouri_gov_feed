"""Run a frontend tool (prettier / eslint) for pre-commit without needing bash.

    python scripts/frontend_hook.py prettier --write --ignore-unknown <files>
    python scripts/frontend_hook.py eslint --fix --no-warn-ignored <files>

pre-commit passes repo-root paths; this strips the `frontend/` prefix and runs `pnpm exec` inside
frontend/. Replaces `bash -c '...'` entries, which broke on Windows when `bash` resolved to WSL.
"""

import shutil
import subprocess
import sys
from pathlib import Path

FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"
PREFIX = "frontend/"


def main() -> int:
    # args before the first path-like arg are tool flags; paths are the ones pre-commit appended
    args = [a[len(PREFIX) :] if a.startswith(PREFIX) else a for a in sys.argv[1:]]
    # shutil.which resolves pnpm.cmd on Windows, which subprocess cannot find by bare name
    pnpm = shutil.which("pnpm")
    if pnpm is None:
        print("pnpm not found on PATH (needs Node 24 + pnpm; see frontend/package.json)", file=sys.stderr)
        return 127
    return subprocess.run([pnpm, "exec", *args], cwd=FRONTEND_DIR, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
