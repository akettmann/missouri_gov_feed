"""Render PlantUML diagrams to SVG next to their sources (pre-commit hook).

    python scripts/render_plantuml.py docs/diagrams/pipeline.puml ...

Uses a pinned plantuml.jar (downloaded once to ~/.cache/plantuml, checksum-verified) and the local
`java` ($JAVA overrides), so diagrams never leave the machine. Exits 1 when any SVG was created or
changed, so the commit stops and the new images can be staged; exits 2 on a diagram syntax error.
"""

import hashlib
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

VERSION = "1.2024.7"
SHA256 = "cb42e3272fedecc0ed20ee0c9cef31873d1c42a489043971038631d357f467e6"
URL = f"https://repo1.maven.org/maven2/net/sourceforge/plantuml/plantuml/{VERSION}/plantuml-{VERSION}.jar"
JAR = Path.home() / ".cache" / "plantuml" / f"plantuml-{VERSION}.jar"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _jar() -> Path:
    if JAR.exists() and _sha256(JAR) == SHA256:
        return JAR
    JAR.parent.mkdir(parents=True, exist_ok=True)
    tmp = JAR.with_suffix(".part")
    with urllib.request.urlopen(URL) as resp, tmp.open("wb") as fh:
        shutil.copyfileobj(resp, fh)
    if _sha256(tmp) != SHA256:
        tmp.unlink()
        sys.exit(f"checksum mismatch for {URL}")
    tmp.replace(JAR)
    return JAR


def _svg(source: Path) -> Path:
    return source.with_suffix(".svg")


def main(paths: list[str]) -> int:
    sources = [Path(p) for p in paths if p.endswith(".puml")]
    if not sources:
        return 0
    java = os.environ.get("JAVA") or shutil.which("java")
    if not java:
        sys.exit("java not found (install a JRE >= 8 or set $JAVA)")
    before = {s: _svg(s).read_bytes() if _svg(s).exists() else None for s in sources}
    # -nometadata keeps the SVG byte-stable (no embedded source/version), so re-renders don't churn
    result = subprocess.run([java, "-jar", str(_jar()), "-tsvg", "-nometadata", "-failfast2", *map(str, sources)])
    if result.returncode != 0:
        return 2
    changed = [s for s in sources if not _svg(s).exists() or _svg(s).read_bytes() != before[s]]
    for s in changed:
        print(f"rendered {_svg(s)}")
    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
