import io
import json
import zipfile
from pathlib import Path

import duckdb

from mogov import db
from mogov.loaders import epa_frs
from mogov.loaders.epa_frs import read_rows

# three rows of MO_ORGANIZATION_FILE.CSV (trimmed to five columns); the second is two records fused onto one
# line by a missing closing quote, as at line 36144 of the October 2026 file
CSV = (
    '"REGISTRY_ID","PGM_SYS_ACRNM","AFFILIATION_TYPE","ORG_NAME","CITY_NAME"\n'
    '"110015893693","RCRAINFO","OWNER","YELLOW FREIGHT SYSTEM INC","OVERLAND PARK"\n'
    '"110015893694","RCRAINFO","OWNER","ACME, INC","O"110015893695","NPDES","OWNER","X","Y"\n'
    '"110015893737","NPDES","OWNER","BURLINGTON JUNCTION RAILWAY","BURLINGTON"\n'
)


def test_rows_land_by_header_and_fused_rows_are_kept():
    rows = list(read_rows(io.StringIO(CSV, newline=""), "MO_ORGANIZATION_FILE.CSV"))
    assert [key for key, _ in rows] == [f"MO_ORGANIZATION_FILE.CSV:{n}" for n in (1, 2, 3)]
    assert rows[0][1] == {
        "REGISTRY_ID": "110015893693",
        "PGM_SYS_ACRNM": "RCRAINFO",
        "AFFILIATION_TYPE": "OWNER",
        "ORG_NAME": "YELLOW FREIGHT SYSTEM INC",
        "CITY_NAME": "OVERLAND PARK",
    }
    # the fused line is one row of the wrong width: kept, not dropped, and it does not swallow the next row
    assert set(rows[1][1]) == {"_fields"} and rows[1][1]["_fields"][0] == "110015893694"
    assert rows[2][1]["ORG_NAME"] == "BURLINGTON JUNCTION RAILWAY"


def test_sic_file_is_landed_verbatim_from_the_state_zip(tmp_path, monkeypatch):
    fixture = Path(__file__).parent / "fixtures" / "epa_frs_sic_excerpt.csv"
    zip_path = tmp_path / "state.zip"
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.writestr("MO_SIC_FILE.CSV", fixture.read_text(encoding="utf-8"))
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(epa_frs, "fetch_to_file", lambda url, dest, max_age: zip_path)
    # a shard that owns only the SIC table, so the other three members are not needed in the fake zip
    monkeypatch.setattr(db.Shard, "owns", lambda self, key: key == "epa_frs_sic")

    assert epa_frs.load(db.UNSHARDED)["epa_frs_sic"] == 3
    rows = duckdb.sql(
        f"select record_key, payload from read_parquet('{db.raw_glob('epa_frs_sic')}') order by record_key"
    ).fetchall()
    assert [k for k, _ in rows] == [f"MO_SIC_FILE.CSV:{n}" for n in (1, 2, 3)]
    first = json.loads(rows[0][1])
    assert first["SIC_CODE"] == "3714" and first["PRIMARY_INDICATOR"] == "UNKNOWN"
    assert first["CODE_DESCRIPTION"] == "MOTOR VEHICLE PARTS AND ACCESSORIES"


def test_alternative_name_file_is_landed_verbatim_from_the_state_zip(tmp_path, monkeypatch):
    # dbt repairs U+FFFD in facility/org names from these (#260), so the padding EPA puts on a name stays as sent
    fixture = Path(__file__).parent / "fixtures" / "epa_frs_alt_names_excerpt.csv"
    zip_path = tmp_path / "state.zip"
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.writestr("MO_ALTERNATIVE_NAME_FILE.CSV", fixture.read_text(encoding="utf-8"))
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(epa_frs, "fetch_to_file", lambda url, dest, max_age: zip_path)
    monkeypatch.setattr(db.Shard, "owns", lambda self, key: key == "epa_frs_alt_names")

    assert epa_frs.load(db.UNSHARDED)["epa_frs_alt_names"] == 3
    rows = duckdb.sql(
        f"select record_key, payload from read_parquet('{db.raw_glob('epa_frs_alt_names')}') order by record_key"
    ).fetchall()
    assert [k for k, _ in rows] == [f"MO_ALTERNATIVE_NAME_FILE.CSV:{n}" for n in (1, 2, 3)]
    first, padded = json.loads(rows[0][1]), json.loads(rows[1][1])
    assert (first["REGISTRY_ID"], first["PGM_SYS_ID"], first["ALTERNATIVE_NAME"]) == (
        "110014353788",
        "MOP000508036",
        "DECOR PLUS",
    )
    assert padded["ALTERNATIVE_NAME"] == "DECOR PLUS" + " " * 70 and padded["ALTERNATIVE_NAME_TYPE"] == "PROGRAM NAME"


def test_alt_names_is_an_optional_raw_table_written_by_this_loader():
    assert db.OPTIONAL_JSON_TABLES["epa_frs_alt_names"] == "epa_frs"
