"""The site_page_violations macro (dbt/macros/site_page_violations.sql) flags fixed bad inputs, and only those."""

from pathlib import Path

import duckdb
import jinja2

MACRO = Path(__file__).resolve().parents[1] / "dbt" / "macros" / "site_page_violations.sql"


def _violations(rows):
    con = duckdb.connect()
    con.execute("create table t (official_id varchar, district_id varchar, registry_id varchar)")
    for row in rows:
        con.execute("insert into t values (?, ?, ?)", row)
    module = jinja2.Environment().from_string(MACRO.read_text(encoding="utf-8")).module
    return con.execute(module.site_page_violations("t")).fetchall()


GOOD = [("o1", "d1", "r1"), ("o1", "d1", "r2"), ("o2", "d2", "r1")]


def test_one_to_one_passes():
    assert _violations(GOOD) == []


def test_two_officials_in_one_district_fail():
    assert _violations([*GOOD, ("o3", "d1", "r3")]) == [("district has several officials", "d1", 2)]


def test_official_in_two_districts_fails():
    assert _violations([*GOOD, ("o2", "d3", "r9")]) == [("official has several districts", "o2", 2)]


def test_repeated_facility_in_a_district_fails():
    assert _violations([*GOOD, ("o1", "d1", "r1")]) == [("facility repeated in a district", "d1 / r1", 2)]
