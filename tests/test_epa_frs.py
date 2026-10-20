import io

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
