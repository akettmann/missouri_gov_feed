"""`mogov load/run` keep going past a failed loader; `run` builds on stale data only when told to."""

import httpx
import pytest

from mogov import cli
from mogov.loaders import senate_efd


@pytest.fixture
def fake_loaders(monkeypatch):
    """Three loaders in three services: `bad` raises, the others land one row. Returns the call log."""
    calls: list[str] = []

    def ok(name):
        def run(_shard):
            calls.append(name)
            return {name: 1}

        return run

    def bad(_shard):
        calls.append("bad")
        raise RuntimeError("upstream is down")

    registry = {"a": ok("a"), "bad": bad, "z": ok("z")}
    monkeypatch.setattr(cli, "REGISTRY", registry)
    monkeypatch.setattr(cli, "SERVICE", {n: n for n in registry})
    monkeypatch.setattr(cli, "STAGE", {n: 1 for n in registry})
    monkeypatch.setattr(cli, "SLOW", set())
    monkeypatch.setattr(cli, "load_all_modules", lambda: None)
    monkeypatch.setattr(cli.db, "migrate_legacy_layout", lambda: None)
    monkeypatch.setattr(cli.obs, "flush", lambda: None)
    return calls


def test_run_loaders_runs_every_loader_and_names_the_failed(fake_loaders):
    failed = cli.run_loaders([], workers=1)
    assert failed == ["bad"]
    assert sorted(fake_loaders) == ["a", "bad", "z"]  # the failure did not stop the others


def test_run_loaders_names_failure_in_one_service_group(fake_loaders, monkeypatch):
    monkeypatch.setattr(cli, "SERVICE", {"a": "x", "bad": "x", "z": "x"})  # same service: run in sequence
    assert cli.run_loaders([], workers=1) == ["bad"]
    assert fake_loaders == ["a", "bad", "z"]


def _main(monkeypatch, *argv):
    monkeypatch.setattr("sys.argv", ["mogov", *argv])
    with pytest.raises(SystemExit) as exc:
        cli.main()
    return exc.value.code


def test_load_exits_nonzero_after_running_everything(fake_loaders, monkeypatch):
    assert _main(monkeypatch, "load", "--workers", "1") == 1
    assert sorted(fake_loaders) == ["a", "bad", "z"]


def test_load_exits_zero_when_all_succeed(fake_loaders, monkeypatch):
    assert _main(monkeypatch, "load", "a", "z", "--workers", "1") == 0


@pytest.fixture
def dbt_calls(monkeypatch):
    calls = []
    monkeypatch.setattr(cli, "run_dbt", lambda args: calls.append(args) or 0)
    return calls


def test_run_is_strict_by_default(fake_loaders, dbt_calls, monkeypatch):
    assert _main(monkeypatch, "run", "--workers", "1") == 1
    assert dbt_calls == []  # no build on top of a failed loader


def test_run_builds_when_the_failed_loader_is_allowed_but_still_exits_nonzero(fake_loaders, dbt_calls, monkeypatch):
    warnings = []
    monkeypatch.setattr(cli.log, "warning", lambda event, **kw: warnings.append((event, kw)))
    code = _main(monkeypatch, "run", "--workers", "1", "--allow-failed-loader", "bad")
    assert code == 1  # Cloud Run still sees the failure
    assert dbt_calls  # but dbt ran
    assert ("build.stale_source", "bad") in [(e, kw["source"]) for e, kw in warnings]


def test_run_allowing_a_different_loader_still_blocks(fake_loaders, dbt_calls, monkeypatch):
    assert _main(monkeypatch, "run", "--workers", "1", "--allow-failed-loader", "a") == 1
    assert dbt_calls == []


def test_run_exits_zero_when_nothing_fails(fake_loaders, dbt_calls, monkeypatch):
    assert _main(monkeypatch, "run", "a", "z", "--workers", "1") == 0
    assert dbt_calls == [["build"]]


def test_run_rejects_unknown_allowed_loader(fake_loaders, dbt_calls, monkeypatch):
    assert "unknown source" in str(_main(monkeypatch, "run", "--allow-failed-loader", "nope"))


def _efd_client(monkeypatch, agreement_status):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(200, text='<input name="csrfmiddlewaretoken" value="tok">')
        return httpx.Response(agreement_status, text="Access Denied")

    real = httpx.Client
    monkeypatch.setattr(senate_efd.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))


def test_senate_efd_fails_fast_on_agreement_403(monkeypatch):
    _efd_client(monkeypatch, 403)
    with pytest.raises(RuntimeError, match=r"agreement POST.*403.*Akamai.*#161"):
        senate_efd._session()


def test_senate_efd_session_ok_when_agreement_accepted(monkeypatch):
    _efd_client(monkeypatch, 200)
    assert senate_efd._session().cookies is not None
