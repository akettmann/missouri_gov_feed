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
