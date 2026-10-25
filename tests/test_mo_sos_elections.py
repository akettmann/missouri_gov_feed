from datetime import date
from pathlib import Path

import duckdb
import pytest

from mogov import db, pdftext
from mogov.loaders import REGISTRY, load_all_modules, mo_sos_elections
from mogov.loaders.mo_sos_elections import elections, parse_pdf

FIXTURES = Path(__file__).parent / "fixtures"
# pages cut from the SoS Grand Totals PDFs: 2024 general pages 1 and 28 (title block, then the Supreme Court
# retention and Court of Appeals blocks), 2024 primary page 1 (party subtotals), 2014 general pages 31 and 32
# (a Court of Appeals block that runs across a page break, with the page furniture the 2014 file repeats)
GENERAL_2024 = FIXTURES / "mo_sos_general_2024_excerpt.pdf"
PRIMARY_2024 = FIXTURES / "mo_sos_primary_2024_excerpt.pdf"
GENERAL_2014 = FIXTURES / "mo_sos_general_2014_excerpt.pdf"


@pytest.fixture(autouse=True)
def _tmp_cache(tmp_path, monkeypatch):
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path / "cache")


def _rows(path: Path) -> list[dict]:
    return parse_pdf(pdftext.page_lines(path.read_bytes()))


def test_results_page_lists_only_statewide_general_and_primary_grand_totals():
    html = (FIXTURES / "mo_sos_results_page_excerpt.html").read_text(encoding="utf-8")
    listed = elections(html)
    # oldest first; no special election, preference primary, county file, turnout file or Election Night Reporting link
    assert [(e["key"], e["type"], e["date"]) for e in listed] == [
        ("2012-11-06-general", "general", date(2012, 11, 6)),
        ("2024-08-06-primary", "primary", date(2024, 8, 6)),
        ("2024-11-05-general", "general", date(2024, 11, 5)),
    ]
    assert listed[-1]["url"] == "https://www.sos.mo.gov/CMSImages/ElectionResultsStatistics/2024GeneralElection.pdf"


def test_candidate_row_cells_come_from_the_column_positions():
    rows = _rows(GENERAL_2024)
    pres = [r for r in rows if r["contest_seq"] == 1 and r["kind"] == "candidate"]
    assert pres[0]["cells"] == {
        "name": "Donald J. Trump, JD Vance",
        "party": "Republican",
        "votes": "1,751,986",
        "pct": "58.5%",
    }
    # a write-in's party is the column's own text, not part of the name
    assert next(r for r in pres if r["cells"]["name"].startswith("Peter Sonski"))["cells"]["party"] == "Write-in"
    # the title block precedes the first contest
    assert [r["kind"] for r in rows[:6]] == ["other"] * 5 + ["header"]
    assert rows[5]["text"] == "U.S. President and Vice President (3573 of 3573 Precincts Reported)"
    assert all(r["contest_seq"] == 0 for r in rows[:5])


def test_every_contest_has_its_printed_total_and_votes_add_up():
    rows = _rows(GENERAL_2024)
    contests = {r["contest_seq"] for r in rows if r["kind"] == "header"}
    for seq in contests:
        mine = [r for r in rows if r["contest_seq"] == seq]
        printed = [int(r["text"].removeprefix("Total Votes ").replace(",", "")) for r in mine if r["kind"] == "total"]
        counted = [int(r["cells"]["votes"].replace(",", "")) for r in mine if r["kind"] == "candidate"]
        # the page cut ends mid-contest: only complete contests carry a total
        if printed:
            assert sum(counted) == printed[0], mine[0]["text"]
    assert len(contests) > 10


def test_retention_rows_split_into_name_yes_and_no():
    rows = _rows(GENERAL_2024)
    broniec = next(r for r in rows if r["kind"] == "candidate" and r["cells"]["name"] == "Kelly C. Broniec")
    assert broniec["cells"] == {"name": "Kelly C. Broniec", "party": "Yes Votes", "votes": "1,634,157", "pct": "63.1%"}
    no_row = rows[rows.index(broniec) + 1]
    assert no_row["cells"] == {"name": "", "party": "No Votes", "votes": "954,663", "pct": "36.9%"}
    assert no_row["contest_seq"] == broniec["contest_seq"]


def test_primary_party_subtotals_are_their_own_kind():
    rows = _rows(PRIMARY_2024)
    senate = [r for r in rows if r["contest_seq"] == 1]
    assert [r["kind"] for r in senate].count("party_total") == 3
    assert next(r for r in senate if r["text"] == "Party Total 378,134")["kind"] == "party_total"
    # the 378,134 Democratic subtotal is the sum of that party's candidates
    democrats = [r for r in senate if r["kind"] == "candidate" and r["cells"]["party"] == "Democratic"]
    assert sum(int(r["cells"]["votes"].replace(",", "")) for r in democrats) == 378134


def test_contest_runs_across_a_page_break_and_page_furniture_is_not_a_contest():
    rows = _rows(GENERAL_2014)
    appeals = [r for r in rows if r["text"].startswith("Court of Appeals")]
    assert appeals, "fixture should reach the Court of Appeals block"
    block = [r for r in rows if r["contest_seq"] == appeals[0]["contest_seq"]]
    assert {r["page"] for r in block} == {1, 2}  # the first judge on one page, the second after the break
    assert [r["kind"] for r in block].count("total") == 2  # a printed total per judge
    furniture = [r for r in rows if r["text"].startswith("*Election Result as of")]
    assert furniture and all(r["kind"] == "other" for r in furniture)


def test_a_percentage_that_lost_its_sign_still_parses_but_a_missing_vote_count_does_not():
    # both quirks are from the 2016 file ("No Votes 252,827 59.5" and "No Votes 40.9%")
    row = parse_pdf([[[("No", 55.0), ("Votes", 70.0), ("252,827", 376.0), ("59.5", 462.0)]]])[0]
    assert row["kind"] == "candidate" and row["cells"]["votes"] == "252,827"
    row = parse_pdf([[[("No", 55.0), ("Votes", 70.0), ("40.9%", 462.0)]]])[0]
    assert row["kind"] == "other"


def test_load_lands_one_raw_row_per_line_with_provenance(tmp_path, monkeypatch):
    html = (FIXTURES / "mo_sos_results_page_excerpt.html").read_bytes()
    by_url = {
        "https://www.sos.mo.gov/CMSImages/ElectionResultsStatistics/2024GeneralElection.pdf": GENERAL_2024,
        "https://www.sos.mo.gov/CMSImages/ElectionResultsStatistics/2024PrimaryElection.pdf": PRIMARY_2024,
        "https://www.sos.mo.gov/CMSImages/ElectionResultsStatistics/2012GeneralElection.pdf": GENERAL_2014,
    }
    fetched = []

    def fake_fetch(url, *args, **kwargs):
        fetched.append(url)
        return html if url == mo_sos_elections.RESULTS_URL else by_url[url].read_bytes()

    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(mo_sos_elections, "fetch", fake_fetch)
    counts = mo_sos_elections.load(db.UNSHARDED)

    raw = db.raw_glob("mo_sos_election_rows")
    rows = duckdb.sql(
        "select record_key, json_extract_string(payload, '$.election_key') e, json_extract_string(payload, '$.kind') k,"
        f" json_extract_string(payload, '$.pdf_url') u, source_url from read_parquet('{raw}')"
    ).fetchall()
    assert counts == {"mo_sos_election_rows": len(rows)}
    assert {e for _, e, *_ in rows} == {"2012-11-06-general", "2024-08-06-primary", "2024-11-05-general"}
    assert all(u == s for _, _, _, u, s in rows)  # the PDF the line came from rides on each row
    assert len({key for key, *_ in rows}) == len(rows)  # keys are election#page.line: unique, so re-runs replace
    assert fetched[0] == mo_sos_elections.RESULTS_URL and len(fetched) == 4


def test_shards_split_the_elections_and_cover_each_exactly_once(tmp_path, monkeypatch):
    html = (FIXTURES / "mo_sos_results_page_excerpt.html").read_bytes()
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(
        mo_sos_elections,
        "fetch",
        lambda url, *a, **k: html if url == mo_sos_elections.RESULTS_URL else PRIMARY_2024.read_bytes(),
    )
    for index in range(2):
        mo_sos_elections.load(db.Shard(index, 2))
    raw = db.raw_glob("mo_sos_election_rows")
    keys = [
        e
        for (e,) in duckdb.sql(
            f"select distinct json_extract_string(payload, '$.election_key') from read_parquet('{raw}')"
        ).fetchall()
    ]
    assert sorted(keys) == ["2012-11-06-general", "2024-08-06-primary", "2024-11-05-general"]


def test_loader_is_registered_with_its_optional_table():
    load_all_modules()
    assert "mo_sos_elections" in REGISTRY
    assert db.OPTIONAL_JSON_TABLES["mo_sos_election_rows"] == "mo_sos_elections"
