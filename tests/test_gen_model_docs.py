"""--check mode of scripts/gen_model_docs.py on a fixed tmp_path models tree."""

import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "gen_model_docs", Path(__file__).resolve().parent.parent / "scripts" / "gen_model_docs.py"
)
gen = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gen)  # the script only writes under __main__, so importing is side-effect free


@pytest.fixture
def models(tmp_path):
    (tmp_path / "staging" / "src").mkdir(parents=True)
    (tmp_path / "intermediate").mkdir()
    (tmp_path / "staging" / "src" / "stg_src__a.sql").write_text("-- Staged a.\nselect 1\n")
    (tmp_path / "intermediate" / "int_judges__current.sql").write_text("-- Sitting judges.\nselect 1\n")
    return tmp_path


def test_check_fails_before_generate_then_passes(models):
    assert gen.main(["--check"], models) == 1
    assert not (models / "intermediate" / "_intermediate.yml").exists()  # check never writes
    assert gen.main([], models) == 0
    assert gen.main(["--check"], models) == 0


def test_check_detects_header_edit(models):
    gen.main([], models)
    (models / "intermediate" / "int_judges__current.sql").write_text("-- Sitting judges, edited.\nselect 1\n")
    assert gen.main(["--check"], models) == 1


def test_hand_written_keys_survive_and_do_not_read_as_stale(models):
    gen.main([], models)
    yml = models / "intermediate" / "_intermediate.yml"
    yml.write_text(
        yml.read_text(encoding="utf-8").replace("  description:", "  data_tests: [x]\n  description:"),
        encoding="utf-8",
    )
    gen.main([], models)
    assert "data_tests" in yml.read_text(encoding="utf-8")
    assert gen.main(["--check"], models) == 0
