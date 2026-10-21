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


@pytest.mark.parametrize(("setting", "bumped"), [("VERSION", "9.9999.9"), ("LAYOUT", "dot")])
def test_renderer_change_makes_stamp_stale(
    diagram: Path, monkeypatch: pytest.MonkeyPatch, setting: str, bumped: str
) -> None:
    def digest() -> str:
        return render_plantuml._stamp(diagram).split("source-sha256=")[1].split()[0]

    before = digest()
    diagram.with_suffix(".svg").write_text(render_plantuml._stamp(diagram) + "<svg/>", encoding="utf-8", newline="\n")
    monkeypatch.setattr(render_plantuml, setting, bumped)
    assert digest() != before, f"{setting} is not part of the stamp hash"
    assert not render_plantuml._is_fresh(diagram), (
        f"changing {setting} left an existing stamp fresh: {setting} must be part of the stamp hash, "
        "or SVGs won't re-render after a renderer change"
    )


def test_crlf_checkout_matches_lf_stamp(diagram: Path) -> None:
    diagram.with_suffix(".svg").write_text(render_plantuml._stamp(diagram) + "<svg/>", encoding="utf-8", newline="\n")
    diagram.write_bytes(diagram.read_bytes().replace(b"\n", b"\r\n"))
    assert render_plantuml._is_fresh(diagram)
