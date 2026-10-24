"""Staleness detection in scripts/sqlfluff_hook.py (subprocess mocked, fixed tmp_path inputs)."""

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "sqlfluff_hook", Path(__file__).resolve().parent.parent / "scripts" / "sqlfluff_hook.py"
)
hook = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(hook)

LOCK = """packages:
  - name: dbt_utils
    package: dbt-labs/dbt_utils
    version: 1.4.1
  - name: dbt_expectations
    package: calogica/dbt_expectations
    version: 0.10.0
sha1_hash: abc
"""


@pytest.fixture
def project(tmp_path):
    (tmp_path / "packages.yml").write_text("packages: []\n")
    (tmp_path / "package-lock.yml").write_text(LOCK)
    return tmp_path


def _install(project, names=("dbt_utils", "dbt_expectations"), marker=True):
    pkgs = project / "dbt_packages"
    pkgs.mkdir()
    for n in names:
        (pkgs / n).mkdir()
    if marker:
        (pkgs / hook.MARKER_NAME).write_text(hook.deps_fingerprint(project))


def test_missing_dir_is_stale(project):
    assert hook.packages_stale(project)


def test_empty_dir_is_stale(project):
    (project / "dbt_packages").mkdir()
    assert hook.packages_stale(project)


def test_missing_one_package_is_stale(project):
    _install(project, names=("dbt_utils",))
    assert hook.packages_stale(project)


def test_changed_lock_is_stale(project):
    _install(project)
    (project / "package-lock.yml").write_text(LOCK.replace("1.4.1", "1.5.0"))
    assert hook.packages_stale(project)


def test_up_to_date(project):
    _install(project)
    assert not hook.packages_stale(project)


def _run_main(monkeypatch, project, deps_rc=0, argv=("lint", "a.sql")):
    calls = []

    def fake_run(cmd, check, **kwargs):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, deps_rc if cmd[0] == "dbt" else 7, stdout=b"All Finished!")

    monkeypatch.setattr(hook, "DBT_DIR", project)
    monkeypatch.setattr(hook.subprocess, "run", fake_run)
    monkeypatch.setattr(sys, "argv", ["hook", *argv])
    return hook.main(), calls


def test_up_to_date_skips_dbt_and_passes_args_and_exit_code(monkeypatch, project):
    _install(project)
    rc, calls = _run_main(monkeypatch, project)
    assert rc == 7
    assert [c[4:] for c in calls] == [["--run-sqlfluff", "lint", "a.sql"]]


def test_stale_runs_deps_then_sqlfluff_and_writes_marker(monkeypatch, project):
    _install(project, names=("dbt_utils",))
    rc, calls = _run_main(monkeypatch, project)
    assert [c[0] == "dbt" for c in calls] == [True, False]
    assert calls[0][1] == "deps"
    assert rc == 7
    assert (project / "dbt_packages" / hook.MARKER_NAME).read_text() == hook.deps_fingerprint(project)


def test_deps_failure_propagates_and_skips_sqlfluff(monkeypatch, project):
    rc, calls = _run_main(monkeypatch, project, deps_rc=3)
    assert rc == 3
    assert [c[0] for c in calls] == ["dbt"]


INTERNAL_ERROR_OUTPUT = (
    "WARNING    Unable to lint dbt/models/x.sql due to an internal error. Please report this as an issue\n"
    "Traceback (most recent call last):\nRecursionError: maximum recursion depth exceeded\nAll Finished!\n"
)


def _fake_run(stdout, returncode=0):
    def run(cmd, **kwargs):
        assert "--run-sqlfluff" in cmd
        return subprocess.CompletedProcess(cmd, returncode, stdout=stdout.encode())

    return run


def test_internal_error_output_is_detected():
    assert hook.has_internal_error(INTERNAL_ERROR_OUTPUT)
    assert not hook.has_internal_error("=== [dbt templater] Project Compiled.\nAll Finished!\n")


def test_internal_error_fails_even_when_sqlfluff_exits_zero(monkeypatch, capsys):
    monkeypatch.setattr(hook.subprocess, "run", _fake_run(INTERNAL_ERROR_OUTPUT, 0))
    assert hook.run_sqlfluff(["lint", "x.sql"]) == 1
    assert "internal error" in capsys.readouterr().err


def test_clean_run_passes(monkeypatch):
    monkeypatch.setattr(hook.subprocess, "run", _fake_run("All Finished!\n", 0))
    assert hook.run_sqlfluff(["lint", "x.sql"]) == 0


def test_lint_violations_keep_sqlfluff_exit_code(monkeypatch):
    monkeypatch.setattr(hook.subprocess, "run", _fake_run("L: 1 | LT05\n", 1))
    assert hook.run_sqlfluff(["lint", "x.sql"]) == 1


@pytest.mark.parametrize(
    ("raised", "expected"),
    [(SystemExit(2), 2), (SystemExit(None), 0), (SystemExit(0), 0), (ValueError("boom"), 1)],
    ids=["exit2", "exit-none", "exit0", "valueerror"],
)
def test_run_sqlfluff_inprocess_exit_code_mapping(monkeypatch, raised, expected):
    from sqlfluff.cli.commands import cli

    def fake_main(**_kwargs):
        raise raised

    monkeypatch.setattr(cli, "main", fake_main)
    monkeypatch.setattr(sys, "setrecursionlimit", lambda _n: None)
    monkeypatch.setattr(hook.threading, "stack_size", lambda _n: 0)
    assert hook.run_sqlfluff_inprocess(["lint", "x.sql"]) == expected


def test_run_sqlfluff_inprocess_returns_zero_when_main_returns(monkeypatch):
    from sqlfluff.cli.commands import cli

    monkeypatch.setattr(cli, "main", lambda **_kwargs: None)
    monkeypatch.setattr(sys, "setrecursionlimit", lambda _n: None)
    monkeypatch.setattr(hook.threading, "stack_size", lambda _n: 0)
    assert hook.run_sqlfluff_inprocess(["lint"]) == 0


def test_run_sqlfluff_forces_utf8_child_and_echoes_bytes(monkeypatch, capsysbinary):
    seen = {}

    def fake_run(cmd, **kwargs):
        seen["cmd"], seen["env"] = cmd, kwargs["env"]
        return subprocess.CompletedProcess(cmd, 0, stdout="café ✓\n".encode(), stderr=None)

    monkeypatch.setattr(hook.subprocess, "run", fake_run)
    assert hook.run_sqlfluff(["lint", "x.sql"]) == 0
    assert seen["env"]["PYTHONIOENCODING"] == "utf-8"
    assert seen["cmd"][1:3] == ["-X", "utf8"]
    assert capsysbinary.readouterr().out == "café ✓\n".encode()
