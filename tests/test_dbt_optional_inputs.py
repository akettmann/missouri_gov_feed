"""The on-run-start hook that stops a bare `dbt build` silently disabling opt-in models (issue #105)."""

import json
import logging
import logging.handlers
import shutil
from pathlib import Path

import duckdb
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


_MODEL = "select 1 as id"
_SNAPSHOT = """{% snapshot hook_snap %}
{{ config(target_schema='snap', unique_key='id', strategy='check', check_cols=['id']) }}
select 1 as id
{% endsnapshot %}
"""
_SOURCES = """version: 2
sources:
  - name: fx
    meta:
      external_location: "read_parquet('{{ var('fx_parquet') }}')"
    freshness:
      warn_after: {count: 100000, period: day}
    loaded_at_field: loaded_at
    tables:
      - name: events
"""
# What each gate checks, copied from the macro's `gates`: (var, raw table directory).
GATES = [("mec_direct", "mec_cd1_a"), ("cl_case_bulk", "cl_mo_opinion_clusters")]
# Subcommands that fire on-run-start (`run-operation` does not, so it cannot prove the wiring).
COMMANDS = [["build"], ["snapshot"], ["source", "freshness"]]


@pytest.fixture(scope="session")
def hook_project(tmp_path_factory):
    """A minimal dbt project holding the real hook macro and the real `on-run-start`, `vars` and `dispatch`.

    Covered: the macro's gates (each var, on its own, against its raw table), the skip var, and that the real
    `on-run-start` fires for `build`, `snapshot` and `source freshness` (the project carries one model, one
    snapshot and one source, because hooks do not fire in a project with no nodes). Not covered: the real
    models, or `mogov build` choosing the vars (see the `run_dbt` test below).

    The real project needs `dbt deps` (dbt_utils) and the duckdb spatial extension (network), which a fresh
    clone or worktree lacks (#357; CI ran `dbt deps` for sqlfluff before pytest, hiding it). The hook needs neither.
    """
    real = yaml.safe_load((DBT_DIR / "dbt_project.yml").read_text(encoding="utf-8"))
    project = tmp_path_factory.mktemp("hook_project")
    for d in ("macros", "models", "snapshots"):
        (project / d).mkdir()
    shutil.copy(DBT_DIR / "macros" / "optional_inputs.sql", project / "macros")
    (project / "models" / "m.sql").write_text(_MODEL, encoding="utf-8")
    (project / "snapshots" / "s.sql").write_text(_SNAPSHOT, encoding="utf-8")
    (project / "models" / "sources.yml").write_text(_SOURCES, encoding="utf-8")
    fx = project / "fx.parquet"
    duckdb.connect().execute(f"copy (select 1 as id, now() as loaded_at) to '{fx.as_posix()}' (format parquet)")
    minimal = {
        "name": real["name"],
        "version": real["version"],
        "config-version": real["config-version"],
        "profile": real["profile"],
        "macro-paths": ["macros"],
        "model-paths": ["models"],
        "snapshot-paths": ["snapshots"],
        "on-run-start": real["on-run-start"],
        "vars": {**real.get("vars", {}), "fx_parquet": fx.as_posix()},
        "dispatch": real["dispatch"],
    }
    (project / "dbt_project.yml").write_text(yaml.safe_dump(minimal), encoding="utf-8")
    profile = {real["profile"]: {"target": "t", "outputs": {"t": {"type": "duckdb", "path": ":memory:"}}}}
    (project / "profiles.yml").write_text(yaml.safe_dump(profile), encoding="utf-8")
    return project


def _dbt(monkeypatch, hook_project, raw_dir, command, vars_=None):
    monkeypatch.setenv("MOGOV_RAW_DIR", raw_dir.as_posix())
    args = [*command, "--project-dir", str(hook_project), "--profiles-dir", str(hook_project)]
    # Keep dbtRunner out of dbt/target (partial_parse.msgpack) and dbt/logs: writing them forces a full reparse
    # (or dirties logs) on the next real dbt run.
    out = raw_dir.parent
    args += ["--target-path", str(out / "dbt_target"), "--log-path", str(out / "dbt_logs")]
    if vars_:
        args += ["--vars", json.dumps(vars_)]
    return dbtRunner().invoke(args)


def _check(monkeypatch, hook_project, raw_dir, vars_=None):
    return _dbt(monkeypatch, hook_project, raw_dir, ["run-operation", "check_optional_inputs"], vars_)


@pytest.fixture(params=GATES, ids=[g[0] for g in GATES])
def gate_raw(request, tmp_path):
    """Raw data for one gate; `other_on` turns on only the OTHER gate's var, so this gate must fail alone."""
    gate, identifier = request.param
    (tmp_path / "raw" / identifier).mkdir(parents=True)
    (tmp_path / "raw" / identifier / "x.parquet").touch()  # the check only globs
    other_on = {g: True for g, _ in GATES if g != gate}
    return tmp_path / "raw", gate, other_on


def _hook_error(result):
    assert not result.success
    assert "optional inputs are loaded but their dbt vars are off" in str(result.exception)


def test_fails_when_raw_exists_and_var_off(monkeypatch, hook_project, gate_raw):
    raw, _gate, other_on = gate_raw
    # run-operation reports the macro's error in the log, not on the result, so only success is checked here
    assert not _check(monkeypatch, hook_project, raw, other_on).success


@pytest.mark.parametrize("command", COMMANDS, ids=" ".join)
def test_hook_fails_dbt_command_when_var_off(monkeypatch, hook_project, gate_raw, command):
    raw, gate, other_on = gate_raw
    result = _dbt(monkeypatch, hook_project, raw, command, other_on or None)
    _hook_error(result)
    assert gate in str(result.exception)


@pytest.mark.parametrize("command", COMMANDS, ids=" ".join)
def test_hook_passes_dbt_command_when_var_on(monkeypatch, hook_project, gate_raw, command):
    raw, gate, other_on = gate_raw
    assert _dbt(monkeypatch, hook_project, raw, command, {**other_on, gate: True}).success


def test_passes_when_vars_on(monkeypatch, hook_project, gate_raw):
    raw, _gate, _other = gate_raw
    assert _check(monkeypatch, hook_project, raw, {g: True for g, _ in GATES}).success


def test_passes_with_explicit_skip(monkeypatch, hook_project, gate_raw):
    raw, _gate, _other = gate_raw
    assert _check(monkeypatch, hook_project, raw, {"skip_optional_raw_check": True}).success


def test_skip_var_skips_dbt_command_hook(monkeypatch, hook_project, gate_raw):
    raw, _gate, _other = gate_raw
    assert _dbt(monkeypatch, hook_project, raw, ["build"], {"skip_optional_raw_check": True}).success


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
