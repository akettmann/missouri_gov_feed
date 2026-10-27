"""house_fd loader on fixed index rows and fake PDFs (no network)."""

import json

import duckdb
import pytest

from mogov import db
from mogov.loaders import house_fd as mod

YEAR = 2022


def _rec(doc_id, filing_type, state="MO04"):
    return {
        "Last": "Doe",
        "FilingType": filing_type,
        "StateDst": state,
        "Year": str(YEAR),
        "DocID": doc_id,
        "FilingDate": "8/11/2023",
    }


INDEX = [
    _rec("1001", "O"),
    _rec("1002", "H"),
    _rec("1003", "P"),
    _rec("1004", "X"),
    _rec("1005", "H", state="TX01"),
]


@pytest.fixture
def served(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    monkeypatch.setattr(mod, "FIRST_YEAR", YEAR)
    monkeypatch.setattr(mod, "_index", lambda year: [{**r, "index_year": year} for r in INDEX] if year == YEAR else [])
    urls = []

    def fake_fetch(url, **kw):
        urls.append(url)
        return b"%PDF-fake"

    monkeypatch.setattr(mod, "fetch", fake_fetch)
    monkeypatch.setattr(mod.pdftext, "page_texts", lambda b, layout=False: ["Filing Type: New Filer Report\nAsset A"])
    return urls


def test_new_filer_h_pdfs_are_downloaded_for_missouri_only(served):
    mod.load(db.UNSHARDED)
    base = f"{mod.BASE}/financial-pdfs/{YEAR}"
    assert sorted(served) == [f"{base}/1001.pdf", f"{base}/1002.pdf", f"{mod.BASE}/ptr-pdfs/{YEAR}/1003.pdf"]
    lines = duckdb.sql(f"select payload from read_parquet('{db.raw_glob('house_fd_pdf_lines')}')").fetchall()
    assert {json.loads(p)["doc_id"] for (p,) in lines} == {"1001", "1002", "1003"}


def test_every_index_row_still_lands_including_unread_types(served):
    counts = mod.load(db.UNSHARDED)
    assert counts["house_fd_index"] == len(INDEX)


def test_extract_timeout_lands_as_an_error_row_and_the_run_goes_on(served, monkeypatch):
    def slow(b, layout=False):
        raise mod.pdftext.ExtractTimeout("text extraction ran past 1 s after 3 pages")

    monkeypatch.setattr(mod.pdftext, "page_texts", slow)
    mod.load(db.UNSHARDED)
    rows = duckdb.sql(f"select payload from read_parquet('{db.raw_glob('house_fd_pdf_lines')}')").fetchall()
    payloads = [json.loads(p) for (p,) in rows]
    assert {p["doc_id"] for p in payloads} == {"1001", "1002", "1003"}
    assert all("ran past" in p["error"] for p in payloads)
