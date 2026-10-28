"""`mogov load/run` keep going past a failed loader; `run` builds on stale data only when told to."""

import json

import httpx
import pytest
import structlog.testing

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
    with structlog.testing.capture_logs() as logs:
        code = _main(monkeypatch, "run", "--workers", "1", "--allow-failed-loader", "bad")
    assert code == 1  # Cloud Run still sees the failure
    assert dbt_calls  # but dbt ran
    assert [(e["event"], e["source"]) for e in logs if e["event"] == "build.stale_source"] == [
        ("build.stale_source", "bad")
    ]


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


def test_allow_failed_loaders_env_merges_with_flags(fake_loaders, monkeypatch):
    monkeypatch.setenv("MOGOV_ALLOW_FAILED_LOADERS", " bad , z,")
    assert cli._allowed_failed(["a"]) == ["a", "bad", "z"]


@pytest.mark.parametrize("value", ["", " ,, "])
def test_allow_failed_loaders_env_empty_means_none(fake_loaders, monkeypatch, value):
    monkeypatch.setenv("MOGOV_ALLOW_FAILED_LOADERS", value)
    assert cli._allowed_failed([]) == []


def test_allow_failed_loaders_env_rejects_unknown_name(fake_loaders, monkeypatch):
    monkeypatch.setenv("MOGOV_ALLOW_FAILED_LOADERS", "bad,nope")
    with pytest.raises(SystemExit, match="unknown source 'nope'"):
        cli._allowed_failed([])


def test_run_builds_when_env_allows_the_failed_loader(fake_loaders, dbt_calls, monkeypatch):
    monkeypatch.setenv("MOGOV_ALLOW_FAILED_LOADERS", "bad")
    assert _main(monkeypatch, "run", "--workers", "1") == 1
    assert dbt_calls  # built on stale data, exit still non-zero


def test_run_rejects_unknown_env_allowed_loader(fake_loaders, dbt_calls, monkeypatch):
    monkeypatch.setenv("MOGOV_ALLOW_FAILED_LOADERS", "nope")
    assert "unknown source" in str(_main(monkeypatch, "run", "--workers", "1"))
    assert dbt_calls == []


@pytest.fixture
def stage2_failing(fake_loaders, monkeypatch):
    """Stage 1 is clean (`a`, `z`); the stage-2 loader `late` raises."""

    def late(_shard):
        fake_loaders.append("late")
        raise RuntimeError("stage 2 is down")

    registry = {"a": cli.REGISTRY["a"], "z": cli.REGISTRY["z"], "late": late}
    monkeypatch.setattr(cli, "REGISTRY", registry)
    monkeypatch.setattr(cli, "SERVICE", {n: n for n in registry})
    monkeypatch.setattr(cli, "STAGE", {"a": 1, "z": 1, "late": 2})
    return fake_loaders


def test_run_blocks_the_second_build_when_a_stage_2_loader_fails(stage2_failing, dbt_calls, monkeypatch):
    assert _main(monkeypatch, "run", "--workers", "1") == 1
    assert "late" in stage2_failing
    assert dbt_calls == [["build"]]  # the stage-1 build ran; the stage-2 one did not


def test_run_runs_the_second_build_when_the_stage_2_failure_is_allowed(stage2_failing, dbt_calls, monkeypatch):
    assert _main(monkeypatch, "run", "--workers", "1", "--allow-failed-loader", "late") == 1  # exit stays non-zero
    assert dbt_calls == [["build"], ["build"]]


def test_run_skip_unit_tests_excludes_them_from_both_builds(stage2_failing, dbt_calls, monkeypatch):
    _main(monkeypatch, "run", "--workers", "1", "--allow-failed-loader", "late", "--skip-unit-tests")
    assert dbt_calls == [["build", "--exclude-resource-type", "unit_test"]] * 2


def test_explanatory_text_survives_cloud_logging_message_rewrite(monkeypatch, capsys):
    """On Cloud Run `event` becomes `message`; an extra `message=` kwarg would be overwritten, so use `hint`."""
    monkeypatch.setenv("CLOUD_RUN_JOB", "mogov")
    monkeypatch.delenv("MOGOV_LOG_JSON", raising=False)
    monkeypatch.setattr(cli.obs, "_configured", False)
    saved_config = cli.structlog.get_config()
    try:
        cli.obs.configure()
        cli._summarize([["bad"]])
        cli._gate_build(["bad"], ["bad"])
        cli._gate_build(["z"], [])
    finally:
        cli.structlog.configure(**saved_config)
    lines = [json.loads(line) for line in capsys.readouterr().err.splitlines() if line.startswith("{")]
    by_message = {line["message"]: line for line in lines}
    assert by_message["loader.summary"]["hint"] == "these loaders failed; their raw data is stale"
    assert "building on its stale raw data" in by_message["build.stale_source"]["hint"]
    assert "--allow-failed-loader" in by_message["build.skipped"]["hint"]
