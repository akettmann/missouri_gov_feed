"""The `local` dbt output must cap DuckDB's memory where DuckDB sees it, and must not spill (#818)."""

from pathlib import Path

import yaml

PROFILES = Path(__file__).resolve().parent.parent / "dbt" / "profiles.yml"


def _local() -> dict:
    return yaml.safe_load(PROFILES.read_text(encoding="utf-8"))["mogov"]["outputs"]["local"]


def test_local_output_sets_duckdb_memory_limit_from_env() -> None:
    limit = _local()["settings"]["memory_limit"]
    assert "env_var('MOGOV_DUCKDB_MEMORY', '4GB')" in limit


def test_local_output_has_no_ignored_top_level_memory_limit() -> None:
    # dbt-duckdb ignores a top-level `memory_limit`; only `settings:` reaches DuckDB.
    assert "memory_limit" not in _local()


def test_local_output_does_not_spill_to_disk() -> None:
    # An empty temp_directory makes a query over memory_limit fail instead of writing temp files.
    assert _local()["settings"]["temp_directory"] == ""
