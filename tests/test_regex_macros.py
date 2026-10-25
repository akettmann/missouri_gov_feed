"""Render dbt/macros/compat/strings.sql for several adapters without a warehouse.

Only DuckDB is tested end to end (dbt build / unit tests). Snowflake and Postgres can't be run here, so these tests
pin the SQL text the macros render for them, and run the DuckDB rendering against real DuckDB.
Patterns below are the real regex as the engine sees it (already Jinja-unescaped).
"""

from pathlib import Path

import duckdb
import jinja2
import pytest

MACROS = Path(__file__).resolve().parents[1] / "dbt" / "macros" / "compat" / "strings.sql"
DOTS = r"j\.d\."


def _macros(adapter: str):
    """The strings.sql macros as a module, with adapter.dispatch resolving like dbt does for `adapter`."""
    env = jinja2.Environment()
    holder = {}

    class Adapter:
        @staticmethod
        def dispatch(name, _package):
            for prefix in (adapter, "default"):
                if hasattr(holder["module"], f"{prefix}__{name}"):
                    return getattr(holder["module"], f"{prefix}__{name}")
            raise KeyError(name)

    class Mogov:  # macros call each other as mogov.<name>
        def __getattr__(self, name):
            return getattr(holder["module"], name)

    env.globals.update(adapter=Adapter, mogov=Mogov(), **{"return": lambda value: value})
    holder["module"] = env.from_string(MACROS.read_text(encoding="utf-8")).module
    module = holder["module"]
    return module


def test_backslash_doubled_for_snowflake_only():
    assert str(_macros("snowflake").regex_matches("x", DOTS)) == r"(regexp_instr(x, 'j\\.d\\.') > 0)"
    assert str(_macros("duckdb").regex_matches("x", DOTS)) == r"regexp_matches(x, 'j\.d\.')"
    assert str(_macros("postgres").regex_matches("x", DOTS)) == r"(x ~ 'j\.d\.')"


def test_quotes_doubled_everywhere():
    for adapter in ("snowflake", "duckdb", "postgres", "default"):
        assert "'it''s'" in str(_macros(adapter).regex_extract("x", "it's"))


def test_snowflake_replace_and_extract_use_escaped_literals():
    m = _macros("snowflake")
    assert str(m.regex_replace_all("x", DOTS, r"\1")) == r"regexp_replace(x, 'j\\.d\\.', '\\1')"
    assert str(m.regex_extract("x", DOTS, 1)) == r"regexp_substr(x, 'j\\.d\\.', 1, 1, 'e', 1)"


@pytest.mark.parametrize(
    ("text", "expected"),
    [("J.D. from X", True), ("JxDx", False), ("j.d.", True), ("jxdx", False)],
)
def test_duckdb_rendering_keeps_the_literal_dot(text, expected):
    sql = str(_macros("duckdb").regex_matches("lower(?)", DOTS))
    assert duckdb.connect().execute("select " + sql, [text]).fetchone()[0] is expected
