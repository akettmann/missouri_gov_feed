"""The on-run-start hook that stops a bare `dbt build` silently disabling opt-in models (issue #105)."""

import json
import logging
import logging.handlers
import shutil
from pathlib import Path

import pytest
import yaml
from dbt.cli.main import dbtRunner

from mogov import cli

DBT_DIR = Path(__file__).resolve().parents[1] / "dbt"


@pytest.fixture(autouse=True)
def _close_dbt_log_files():
    # dbt swaps its dbt.log handler per invocation with `handlers.clear()`, leaking the open file (ResourceWarning).
    yield
    for log in logging.Logger.manager.loggerDict.values():
        for h in getattr(log, "handlers", []):
            if isinstance(h, logging.handlers.RotatingFileHandler):
                h.close()


@pytest.fixture(scope="session")
def hook_project(tmp_path_factory):
    """A minimal dbt project holding only the real hook macro and the real `on-run-start` wiring.

    The real project needs `dbt deps` (dbt_utils) and the duckdb spatial extension (network), which a fresh
    clone or worktree lacks (#357; CI ran `dbt deps` for sqlfluff before pytest, hiding it). The hook needs neither.
    """
    real = yaml.safe_load((DBT_DIR / "dbt_project.yml").read_text(encoding="utf-8"))
    project = tmp_path_factory.mktemp("hook_project")
    (project / "macros").mkdir()
    shutil.copy(DBT_DIR / "macros" / "optional_inputs.sql", project / "macros")
    minimal = {
        "name": real["name"],
        "version": real["version"],
        "config-version": real["config-version"],
        "profile": real["profile"],
        "macro-paths": ["macros"],
        "on-run-start": real["on-run-start"],
    }
    (project / "dbt_project.yml").write_text(yaml.safe_dump(minimal), encoding="utf-8")
    profile = {real["profile"]: {"target": "t", "outputs": {"t": {"type": "duckdb", "path": ":memory:"}}}}
    (project / "profiles.yml").write_text(yaml.safe_dump(profile), encoding="utf-8")
    return project


def _check(monkeypatch, hook_project, raw_dir, *vars_):
    monkeypatch.setenv("MOGOV_RAW_DIR", raw_dir.as_posix())
    args = ["run-operation", "check_optional_inputs", "--project-dir", str(hook_project)]
    args += ["--profiles-dir", str(hook_project)]
    # Keep dbtRunner out of dbt/target (partial_parse.msgpack) and dbt/logs: writing them forces a full reparse
    # (or dirties logs) on the next real dbt run.
    out = raw_dir.parent
    args += ["--target-path", str(out / "dbt_target"), "--log-path", str(out / "dbt_logs")]
    if vars_:
        args += ["--vars", json.dumps(vars_[0])]
    return dbtRunner().invoke(args)


@pytest.fixture
def raw_with_mec(tmp_path):
    (tmp_path / "raw" / "mec_cd1_a").mkdir(parents=True)
    (tmp_path / "raw" / "mec_cd1_a" / "x.parquet").touch()  # the check only globs
    return tmp_path / "raw"


def test_fails_when_raw_exists_and_var_off(monkeypatch, hook_project, raw_with_mec):
    assert not _check(monkeypatch, hook_project, raw_with_mec).success


def test_passes_when_vars_on(monkeypatch, hook_project, raw_with_mec):
    assert _check(monkeypatch, hook_project, raw_with_mec, {"mec_direct": True, "cl_case_bulk": True}).success


def test_passes_with_explicit_skip(monkeypatch, hook_project, raw_with_mec):
    assert _check(monkeypatch, hook_project, raw_with_mec, {"skip_optional_raw_check": True}).success


def test_passes_with_no_raw_data(monkeypatch, hook_project, tmp_path):
    (tmp_path / "raw").mkdir()
    assert _check(monkeypatch, hook_project, tmp_path / "raw").success


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
    assert yaml.safe_load(cmd[cmd.index("--vars") + 1]) == {"mec_direct": True, "cl_case_bulk": True}
