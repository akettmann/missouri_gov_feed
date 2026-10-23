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

    def fake_run(cmd, check):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, deps_rc if cmd[0] == "dbt" else 7)

    monkeypatch.setattr(hook, "DBT_DIR", project)
    monkeypatch.setattr(hook.subprocess, "run", fake_run)
    monkeypatch.setattr(sys, "argv", ["hook", *argv])
    return hook.main(), calls


def test_up_to_date_skips_dbt_and_passes_args_and_exit_code(monkeypatch, project):
    _install(project)
    rc, calls = _run_main(monkeypatch, project)
    assert rc == 7
    assert calls == [["sqlfluff", "lint", "a.sql"]]


def test_stale_runs_deps_then_sqlfluff_and_writes_marker(monkeypatch, project):
    _install(project, names=("dbt_utils",))
    rc, calls = _run_main(monkeypatch, project)
    assert [c[0] for c in calls] == ["dbt", "sqlfluff"]
    assert calls[0][1] == "deps"
    assert rc == 7
    assert (project / "dbt_packages" / hook.MARKER_NAME).read_text() == hook.deps_fingerprint(project)


def test_deps_failure_propagates_and_skips_sqlfluff(monkeypatch, project):
    rc, calls = _run_main(monkeypatch, project, deps_rc=3)
    assert rc == 3
    assert [c[0] for c in calls] == ["dbt"]
