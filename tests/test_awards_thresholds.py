"""The awards_thresholds macro (dbt/macros/awards_thresholds.sql) rejects bad awards_threshold vars."""

from pathlib import Path

import jinja2
import pytest

MACRO = Path(__file__).resolve().parents[1] / "dbt" / "macros" / "awards_thresholds.sql"


class CompilerError(Exception):
    pass


class MacroReturn(Exception):  # dbt's return() also unwinds with an exception
    pass


def _thresholds(value):
    class Exceptions:
        @staticmethod
        def raise_compiler_error(message):
            raise CompilerError(message)

    def macro_return(result):
        raise MacroReturn(result)

    env = jinja2.Environment()
    env.globals.update(var=lambda name: value, exceptions=Exceptions, **{"return": macro_return})
    module = env.from_string(MACRO.read_text(encoding="utf-8")).module
    try:
        module.awards_thresholds()
    except MacroReturn as returned:
        return returned.args[0]
    raise AssertionError("macro did not return")


def test_valid_var_is_returned():
    value = {"default": 5, "lowest_attendance": 3, "most_party_loyal": 10}
    assert _thresholds(value) == value


def test_default_alone_is_valid():
    assert _thresholds({"default": 5}) == {"default": 5}


@pytest.mark.parametrize(
    ("value", "message"),
    [
        ({"default": 5, "lowest_attendence": 3}, "unknown award 'lowest_attendence'"),
        ({"default": 5, "lowest_attendance": "3"}, "whole number"),
        ({"default": 5, "lowest_attendance": 2.5}, "whole number"),
        ({"default": 5, "lowest_attendance": True}, "whole number"),
        ({"default": 5, "lowest_attendance": -1}, "whole number"),
        ({"default": "five"}, "whole number"),
        ({"lowest_attendance": 3}, "'default' key"),
    ],
)
def test_bad_var_raises_compiler_error(value, message):
    with pytest.raises(CompilerError, match=message):
        _thresholds(value)
