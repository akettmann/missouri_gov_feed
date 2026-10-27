"""Run dbt/macros/contact_redaction.sql against real DuckDB on fixed strings (#711).

Covers the build-failing guard (has_contact_string), the warn-level check (has_phone_like_digits) and redaction
(redact_contact), without a warehouse or a dbt run.
"""

from pathlib import Path

import duckdb
import jinja2
import pytest

MACRO_DIR = Path(__file__).resolve().parents[1] / "dbt" / "macros"


def _module():
    env = jinja2.Environment()
    holder = {}

    class Adapter:
        @staticmethod
        def dispatch(name, _package):
            for prefix in ("duckdb", "default"):
                if hasattr(holder["strings"], f"{prefix}__{name}"):
                    return getattr(holder["strings"], f"{prefix}__{name}")
            raise KeyError(name)

    class Mogov:  # macros call each other as mogov.<name>
        def __getattr__(self, name):
            for key in ("redaction", "strings"):
                if hasattr(holder[key], name):
                    return getattr(holder[key], name)
            raise AttributeError(name)

    env.globals.update(adapter=Adapter, mogov=Mogov(), **{"return": lambda value: value})
    for key, path in (("strings", "compat/strings.sql"), ("redaction", "contact_redaction.sql")):
        holder[key] = env.from_string((MACRO_DIR / path).read_text(encoding="utf-8")).module
    return holder["redaction"]


M = _module()


def _eval(sql_expr: str, text: str):
    """Evaluate the macro's SQL with `__T__` standing for the text (a literal: the guard repeats the expression)."""
    literal = "'" + text.replace("'", "''") + "'"
    return duckdb.connect().execute("select " + sql_expr.replace("__T__", literal)).fetchone()[0]


def _guard(text):
    return _eval(str(M.has_contact_string("__T__")), text)


def _warn(text):
    return _eval(str(M.has_phone_like_digits("__T__")), text)


def _redact(text):
    return _eval(str(M.redact_contact("__T__")), text)


@pytest.mark.parametrize(
    "text",
    [
        "751 6662",
        "Call 751 6662 now",
        "1573 751 1167",
        "1573.751.1167",
        "5737511167",
        "(573) 751-1167",
        "a@b.com",
        "x @ y",
        "100 1000 dollars",  # acceptable loud failure
    ],
)
def test_guard_fails_on_phone_shapes_left_in_redacted_text(text):
    assert _guard(text) is True


@pytest.mark.parametrize(
    "text",
    [
        "SB 123 4567",
        "See HB 100 1234 and SB 123 4567",
        "HCR 12 3456",
        "HJR 5 1234",
        "Call [phone removed],[phone removed] today",
        "[phone removed] [phone removed] [phone removed]",
        "2001-2013 session",
        "Room 117, 8:00 AM",
        "",
    ],
)
def test_guard_passes_on_clean_redacted_text(text):
    assert _guard(text) is False


@pytest.mark.parametrize("text", ["751 6662", "751.6662", "12345678", "573-751 1167", "573 751 1167"])
def test_warn_flags_digit_runs_the_pattern_skips(text):
    assert _warn(text) is True


@pytest.mark.parametrize("text", ["Room 117", "2001-2013", "[phone removed]", "HB 1234", "1,234,567"])
def test_warn_ignores_ordinary_numbers(text):
    assert _warn(text) is False


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Call 751-6662 now", "Call [phone removed] now"),
        ("+1(573)751-1167", "[phone removed]"),
        ("1-573-751-1167", "[phone removed]"),
        ("751-6662,751-1167", "[phone removed],[phone removed]"),
        ("751-6662 751-1167 751-1168", "[phone removed] [phone removed] [phone removed]"),
        ("SB 123 4567", "SB 123 4567"),
        ("751 6662", "751 6662"),  # left for the guard / warn check
        ("mail a.b@c.gov.", "mail [email removed]."),
    ],
)
def test_redaction(text, expected):
    assert _redact(text) == expected
