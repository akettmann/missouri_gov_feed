import json
from pathlib import Path

import duckdb
import pytest

from mogov import db, pdftext
from mogov.loaders import mo_auditor

FIXTURES = Path(__file__).parent / "fixtures"
# State Auditor Citizens Summary for Scott County (report 2018-063), as served by CitzSummaryDirect?id=676
SCOTT_COUNTY_PDF = FIXTURES / "mo_auditor_citizens_summary_676.pdf"
# SearchAudits rows (verbatim) for 2018-063, 2018-062, 2018-001, 2026-091, 2026-086, 2026-050
SEARCH = json.loads((FIXTURES / "mo_auditor_search_excerpt.json").read_text(encoding="utf-8"))["data"]
BY_NUMBER = {mo_auditor.report_number(r): r for r in SEARCH}


@pytest.fixture
def raw_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    return tmp_path


def test_extract_rating_from_the_real_summary_pdf(tmp_path, monkeypatch):
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path)
    pages = pdftext.page_texts(SCOTT_COUNTY_PDF.read_bytes(), max_pages=4)
    assert mo_auditor.extract_rating(pages) == {
        "rating_sentence": "In the areas audited, the overall performance of this entity was Good.",
        "rating_word": "Good",
        "page": 1,
        "n_sentences": 1,
    }


def test_the_rating_legend_is_not_mistaken_for_a_rating():
    legend = (
        "*The rating(s) cover only audited areas. Excellent: The audit results indicate this entity is very well "
        "managed. Good: The audit results indicate this entity is well managed. Fair: ... Poor: ..."
    )
    assert mo_auditor.extract_rating([legend])["rating_sentence"] is None


@pytest.mark.parametrize(
    ("text", "word"),
    [
        # pdfplumber split a word of the sentence in the Stoddard County summary (2018-012)
        ("In the areas au dited, the overall performance of this entity was Fair.*", "Fair"),
        # the sentence wrapped over two lines
        ("In the areas audited, the overall performance of\nthis entity was Poor.*", "Poor"),
        ("In the areas audited, the overall performance of this entity was Excellent.", "Excellent"),
        ("in the areas audited the overall performance of this entity was Good.", "Good"),
    ],
)
def test_extract_rating_tolerates_extraction_noise(text, word):
    assert mo_auditor.extract_rating(["Findings ...", text])["rating_word"] == word
    assert mo_auditor.extract_rating(["Findings ...", text])["page"] == 2


def test_extract_rating_without_a_sentence_and_with_two():
    none = mo_auditor.extract_rating(["Timeliness of refunds: no overall rating."])
    assert none == {"rating_sentence": None, "rating_word": None, "page": None, "n_sentences": 0}
    two = mo_auditor.extract_rating(["x", "overall performance of this entity was Fair.", ""])
    assert two["n_sentences"] == 0  # the sentence needs its lead-in, so a fragment is not a rating
    both = mo_auditor.extract_rating(
        [
            "In the areas audited, the overall performance of this entity was Fair.",
            "In the areas audited, the overall performance of this entity was Good.",
        ]
    )
    assert (both["rating_word"], both["page"], both["n_sentences"]) == ("Fair", 1, 2)


def test_rating_source_picks_the_summary_then_the_full_report_and_skips_unrated_filings():
    assert mo_auditor.rating_source(BY_NUMBER["2018063"]) == (
        "citizens_summary",
        "https://auditor.mo.gov/AuditReport/CitzSummaryDirect?id=676",
    )
    kind, url = mo_auditor.rating_source(BY_NUMBER["2026050"])  # Lieutenant Governor: no summary id
    assert kind == "full_report"
    assert url == "https://auditor.mo.gov" + BY_NUMBER["2026050"]["full_rpt_link"].removeprefix("~")
    assert mo_auditor.rating_source(BY_NUMBER["2026091"]) is None  # county "Financial Statements"
    assert mo_auditor.rating_source(BY_NUMBER["2018062"]) is None  # follow-up report
    old = {**BY_NUMBER["2026050"], "rpt_number": "2005103   "}
    assert mo_auditor.rating_source(old) is None  # before the rating scale


def test_list_year_fails_loudly_on_the_row_cap(monkeypatch):
    capped = {"data": [{}] * 1000, "numTotalRecords": 1000}
    monkeypatch.setattr(mo_auditor, "fetch", lambda *a, **k: json.dumps(capped).encode())
    with pytest.raises(RuntimeError, match="1,000-row cap"):
        mo_auditor.list_year(2018)


def _rows(raw_dir, table):
    path = (raw_dir / table).as_posix()
    return duckdb.sql(f"select record_key, payload from read_parquet('{path}/*.parquet') order by 1").fetchall()


def test_load_is_sharded_idempotent_and_keeps_the_search_record_verbatim(raw_dir, monkeypatch):
    monkeypatch.setattr(mo_auditor, "FIRST_YEAR", 2018)
    monkeypatch.setattr(mo_auditor, "LAST_YEAR", 2018)
    monkeypatch.setattr(mo_auditor, "list_year", lambda year: SEARCH)
    reads = []

    def fake_read(kind, url):
        reads.append(url)
        return {"source_kind": kind, "pdf_url": url, "status": "ok", "rating_word": "Good"}

    monkeypatch.setattr(mo_auditor, "read_rating", fake_read)
    for i in range(2):
        mo_auditor.load(db.Shard(i, 2))
    reports = _rows(raw_dir, "mo_auditor_reports")
    assert [k for k, _ in reports] == sorted(BY_NUMBER)  # every report exactly once across the two shards
    stored = json.loads(dict(reports)["2018063"])
    assert stored == {"search_year": 2018, **BY_NUMBER["2018063"]}  # the record as published, plus the year asked
    ratings = _rows(raw_dir, "mo_auditor_ratings")
    assert [k for k, _ in ratings] == ["2018001", "2018063", "2026050", "2026086"]  # only reports with a rating source
    assert len(reads) == 4

    again = [mo_auditor.load(db.Shard(i, 2)) for i in range(2)]  # re-run replaces each shard's own part
    assert _rows(raw_dir, "mo_auditor_reports") == reports
    assert sum(c["mo_auditor_reports"] for c in again) == len(SEARCH)


def _filing(title, number="2012008   ", **extra):
    return {
        "rpt_number": number,
        "title": title,
        "citz_sum_fk": None,
        "full_rpt_link": "~/Repository/Press/x.pdf",
        **extra,
    }


@pytest.mark.parametrize(
    ("title", "read"),
    [
        # the full report of Monarch FPD (2012-008) rates it Fair, so it must be read
        ("Monarch Fire Protection District", True),
        ("Northeast Ambulance and Fire Protection District", True),
        # county-wide reviews of every district in the county carry no rating sentence
        ("Greene County Fire Protection Districts", False),
        ("St. Louis County Fire Protection District", False),
        ("St. Louis County Fire Protection Districts / Years Ended December 31, 2006", False),
        # a single district whose name carries the county is still rated (2013-062)
        ("Southern Dallas County Fire Protection District", True),
        ("Western Cass County Fire Protection District", True),
        ("Review of Independent Audits of Fire Protection Districts in Greene County", False),
        # singular and plural financial statement filings are both unrated
        ("St. Clair County Financial Statement", False),
        ("Scott County Financial Statements", False),
    ],
)
def test_rating_source_reads_a_single_fire_district_but_not_county_wide_reviews(title, read):
    assert (mo_auditor.rating_source(_filing(title)) is not None) is read


@pytest.mark.parametrize(
    "title",
    [
        # CAFR: the Auditor's title until 2021 (2013-009)
        "Comprehensive Annual Financial Report / Year Ended June 30, 2012",
        # ACFR: the word order since 2022, which "annual (financial) report" alone does not match
        "State of Missouri Annual Comprehensive Financial Report / Year Ended June 30, 2025",
        "Annual Comprehensive Financial Report - Report on Internal Control, Compliance, and Other Matters",
    ],
)
def test_rating_source_skips_annual_financial_reports_even_with_a_pdf(title):
    assert mo_auditor.rating_source(_filing(title)) is None


def test_requests_are_throttled_across_shards_not_slept_per_process(monkeypatch):
    calls = []

    def fake_fetch(url, params=None, **kw):
        calls.append(kw)
        return json.dumps({"data": [], "numTotalRecords": 0}).encode() if params else b""

    monkeypatch.setattr(mo_auditor, "fetch", fake_fetch)
    monkeypatch.setattr(pdftext, "page_texts", lambda *a, **k: [])
    mo_auditor.list_year(2018)
    mo_auditor.read_rating("full_report", "https://auditor.mo.gov/x.pdf")
    assert len(calls) == 2
    for kw in calls:  # min_interval is the host-wide lock shared by every shard; delay would be per process
        assert kw["min_interval"] == mo_auditor.DELAY
        assert "delay" not in kw
