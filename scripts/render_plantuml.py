"""Render PlantUML diagrams to SVG next to their sources (pre-commit hook).

    python scripts/render_plantuml.py docs/diagrams/pipeline.puml ...

Uses a pinned plantuml.jar (downloaded once to ~/.cache/plantuml, checksum-verified) and the local
`java` ($JAVA overrides), so diagrams never leave the machine.

Layout uses Smetana, PlantUML's built-in port of Graphviz, so no `dot` binary is needed on any machine
(Windows, macOS, CI). Text widths still come from the local Java fonts, so two machines can lay out the
same source a few pixels apart. Freshness therefore isn't a byte comparison: each SVG starts with a stamp
holding a hash of its source, the jar version and the layout, and a diagram is re-rendered only when that
stamp is missing or stale. CI checks the stamps without depending on its own fonts.

Exits 1 when any SVG was created or changed, so the commit stops and the new images can be staged;
exits 2 on a diagram syntax error.
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
LAYOUT = "smetana"
STAMP_PREFIX = "<!-- render_plantuml.py source-sha256="


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


def _stamp(source: Path) -> str:
    """One-line SVG comment naming what the image was rendered from (line endings normalized)."""
    h = hashlib.sha256(f"plantuml {VERSION} layout {LAYOUT}\n".encode())
    h.update(source.read_bytes().replace(b"\r\n", b"\n"))
    return f"{STAMP_PREFIX}{h.hexdigest()} plantuml={VERSION} layout={LAYOUT} -->\n"


def _is_fresh(source: Path) -> bool:
    svg = _svg(source)
    if not svg.exists():
        return False
    with svg.open(encoding="utf-8", newline="") as fh:
        return fh.readline() == _stamp(source)


def main(paths: list[str]) -> int:
    stale = [s for s in (Path(p) for p in paths if p.endswith(".puml")) if not _is_fresh(s)]
    if not stale:
        return 0
    java = os.environ.get("JAVA") or shutil.which("java")
    if not java:
        sys.exit("java not found (install a JRE >= 8 or set $JAVA)")
    # -nometadata keeps the source out of the SVG (the stamp carries its hash instead)
    cmd = [java, "-jar", str(_jar()), "-tsvg", "-nometadata", "-failfast2", f"-Playout={LAYOUT}"]
    if subprocess.run([*cmd, *map(str, stale)]).returncode != 0:
        return 2
    for s in stale:
        svg = _svg(s)
        body = svg.read_text(encoding="utf-8")
        svg.write_text(_stamp(s) + body, encoding="utf-8", newline="\n")
        print(f"rendered {svg}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
