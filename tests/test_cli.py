import datetime

import pytest
import yaml

from mogov import cli


def test_jobs_group_services_and_start_slow_ones_first(monkeypatch):
    monkeypatch.setattr(cli, "SERVICE", {"a": "x", "b": "x", "c": "y", "d": "z"})
    monkeypatch.setattr(cli, "SLOW", {"d"})
    jobs = [(group, s.index) for group, s in cli._jobs(["a", "b", "c", "d"], 2, range(2))]
    assert jobs == [
        (["d"], 0),
        (["d"], 1),
        (["a", "b"], 0),  # one service: run one after another
        (["c"], 0),
        (["a", "b"], 1),
        (["c"], 1),
    ]


def test_jobs_for_one_shard(monkeypatch):
    monkeypatch.setattr(cli, "SERVICE", {"a": "x", "c": "y"})
    monkeypatch.setattr(cli, "SLOW", set())
    assert [(g, s.index, s.count) for g, s in cli._jobs(["a", "c"], 4, [2])] == [(["a"], 2, 4), (["c"], 2, 4)]


def test_export_defaults_to_parquet(monkeypatch):
    # The frontend reads only data/exports/*.parquet, so a bare `mogov export` must write parquet.
    seen = []
    monkeypatch.setattr(cli, "export", seen.append)
    monkeypatch.setattr("sys.argv", ["mogov", "export"])
    cli.main()
    monkeypatch.setattr("sys.argv", ["mogov", "export", "--format", "csv"])
    cli.main()
    assert seen == ["parquet", "csv"]


def _dbt_cmd(monkeypatch, args):
    calls = []
    monkeypatch.setattr(cli.db, "ensure_optional_tables", lambda: [])
    monkeypatch.setattr(cli.db, "raw_exists", lambda _name: False)
    monkeypatch.setattr(cli.subprocess, "call", lambda cmd, **_kw: calls.append(cmd) or 0)
    monkeypatch.setattr(cli.subprocess, "check_call", lambda *_a, **_kw: 0)
    assert cli.run_dbt(args) == 0
    return calls[0]


@pytest.mark.parametrize(
    "user_args",
    [
        ["--vars", '{"mec_direct": true, "x": 1}'],
        ['--vars={"mec_direct": true, "x": 1}'],
        ["--vars", "{mec_direct: true, x: 1}"],  # dbt parses YAML
        ["--vars", "mec_direct: true\nx: 1"],
    ],
)
def test_run_dbt_merges_user_vars_with_user_winning(monkeypatch, user_args):
    cmd = _dbt_cmd(monkeypatch, ["build", "--select", "m", *user_args])
    assert sum(a == "--vars" or a.startswith("--vars=") for a in cmd) == 1
    assert yaml.safe_load(cmd[cmd.index("--vars") + 1]) == {"mec_direct": True, "cl_case_bulk": False, "x": 1}
    assert cmd[cmd.index("build") : cmd.index("build") + 3] == ["build", "--select", "m"]


def test_run_dbt_without_user_vars_passes_only_mogov_vars(monkeypatch):
    cmd = _dbt_cmd(monkeypatch, ["build"])
    assert yaml.safe_load(cmd[cmd.index("--vars") + 1]) == {"mec_direct": False, "cl_case_bulk": False}


@pytest.mark.parametrize("bad", [["--vars"], ["--vars", "{a: [}"], ["--vars", "[1, 2]"], ["--vars=just a string"]])
def test_run_dbt_rejects_malformed_user_vars(monkeypatch, bad):
    with pytest.raises(SystemExit) as exc:
        _dbt_cmd(monkeypatch, ["build", *bad])
    assert "--vars" in str(exc.value)


def test_run_dbt_keeps_yaml_dates_typed(monkeypatch):
    cmd = _dbt_cmd(monkeypatch, ["build", "--vars", "{since: 2024-01-01, at: 2024-01-01 10:30:00, s: '2024-01-01'}"])
    # dbt parses the flag as YAML: it must read the same types as when the user passes the flag directly.
    got = yaml.safe_load(cmd[cmd.index("--vars") + 1])
    assert got["since"] == datetime.date(2024, 1, 1)
    assert got["at"] == datetime.datetime(2024, 1, 1, 10, 30)
    assert got["s"] == "2024-01-01"
    assert got["mec_direct"] is False


def test_merge_user_vars_is_shallow_and_later_flag_wins():
    rest, merged = cli._merge_user_vars(
        ["x", "--vars", "{a: 1, n: {p: 1}}", "--vars={a: 2, n: {q: 2}, mec_direct: false}"],
        {"mec_direct": True, "cl_case_bulk": True},
    )
    assert rest == ["x"]
    assert merged == {"mec_direct": False, "cl_case_bulk": True, "a": 2, "n": {"q": 2}}
