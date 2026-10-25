"""The on-run-start hook that stops a bare `dbt build` silently disabling opt-in models (issue #105)."""

import json
from pathlib import Path

import pytest
from dbt.cli.main import dbtRunner

from mogov import cli

DBT_DIR = Path(__file__).resolve().parents[1] / "dbt"


def _check(monkeypatch, raw_dir, *vars_):
    monkeypatch.setenv("MOGOV_RAW_DIR", raw_dir.as_posix())
    args = ["run-operation", "check_optional_inputs", "--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    args += ["--target", "lint"]
    if vars_:
        args += ["--vars", json.dumps(vars_[0])]
    return dbtRunner().invoke(args)


@pytest.fixture
def raw_with_mec(tmp_path):
    (tmp_path / "raw" / "mec_cd1_a").mkdir(parents=True)
    (tmp_path / "raw" / "mec_cd1_a" / "x.parquet").touch()  # the check only globs
    return tmp_path / "raw"


def test_fails_when_raw_exists_and_var_off(monkeypatch, raw_with_mec):
    assert not _check(monkeypatch, raw_with_mec).success


def test_passes_when_vars_on(monkeypatch, raw_with_mec):
    assert _check(monkeypatch, raw_with_mec, {"mec_direct": True, "cl_case_bulk": True}).success


def test_passes_with_explicit_skip(monkeypatch, raw_with_mec):
    assert _check(monkeypatch, raw_with_mec, {"skip_optional_raw_check": True}).success


def test_passes_with_no_raw_data(monkeypatch, tmp_path):
    (tmp_path / "raw").mkdir()
    assert _check(monkeypatch, tmp_path / "raw").success


@pytest.mark.parametrize("args", [["build"], ["source", "freshness"], ["snapshot"]])
def test_run_dbt_passes_vars_to_every_subcommand(monkeypatch, args):
    # dbt runs the hook for `source freshness` too, so a missing --vars there breaks `mogov freshness`.
    calls = []
    monkeypatch.setattr(cli.db, "ensure_optional_tables", lambda: [])
    monkeypatch.setattr(cli.db, "raw_exists", lambda _name: True)
    monkeypatch.setattr(cli.subprocess, "call", lambda cmd, **_kw: calls.append(cmd) or 0)
    monkeypatch.setattr(cli.subprocess, "check_call", lambda *_a, **_kw: 0)
    assert cli.run_dbt(args) == 0
    cmd = calls[0]
    assert json.loads(cmd[cmd.index("--vars") + 1]) == {"mec_direct": True, "cl_case_bulk": True}
