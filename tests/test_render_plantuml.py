"""The PlantUML hook's freshness stamp: no java needed when every SVG matches its source."""

import importlib.util
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "render_plantuml.py"
_spec = importlib.util.spec_from_file_location("render_plantuml", SCRIPT)
render_plantuml = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(render_plantuml)


@pytest.fixture
def diagram(tmp_path: Path) -> Path:
    src = tmp_path / "d.puml"
    src.write_bytes(b"@startuml\nA -> B\n@enduml\n")
    return src


def test_missing_svg_is_stale(diagram: Path) -> None:
    assert not render_plantuml._is_fresh(diagram)


def test_stamped_svg_is_fresh_and_skips_java(diagram: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    diagram.with_suffix(".svg").write_text(render_plantuml._stamp(diagram) + "<svg/>", encoding="utf-8", newline="\n")
    monkeypatch.setattr(render_plantuml.subprocess, "run", lambda *a, **k: pytest.fail("java should not run"))
    assert render_plantuml.main([str(diagram)]) == 0


def test_edited_source_is_stale(diagram: Path) -> None:
    diagram.with_suffix(".svg").write_text(render_plantuml._stamp(diagram) + "<svg/>", encoding="utf-8", newline="\n")
    diagram.write_bytes(b"@startuml\nA -> C\n@enduml\n")
    assert not render_plantuml._is_fresh(diagram)


def test_crlf_checkout_matches_lf_stamp(diagram: Path) -> None:
    diagram.with_suffix(".svg").write_text(render_plantuml._stamp(diagram) + "<svg/>", encoding="utf-8", newline="\n")
    diagram.write_bytes(diagram.read_bytes().replace(b"\n", b"\r\n"))
    assert render_plantuml._is_fresh(diagram)
