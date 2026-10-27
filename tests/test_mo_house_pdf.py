import hashlib
import json
import os
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import ClassVar

import duckdb
import pytest

from mogov import db, pdftext
from mogov.loaders import mo_house_pdf as m

HOST = "https://documents.house.mo.gov/billtracking"
TEXT_1 = f"{HOST}/bills171/hlrbillspdf/0001H.01I.pdf"
TEXT_2 = f"{HOST}/bills171/hlrbillspdf/0002H.01I.pdf"
SUMMARY = f"{HOST}/bills171/sumpdf/HB0001I.pdf"  # linked by two bill versions
FISCAL = f"{HOST}/bills171/fiscal/fispdf/0563-01N.ORG.pdf"
DEAD = "http://www.moga.mo.gov/OverSight/over20181/fiscover/fHB3135.htm"
AMEND = f"{HOST}/bills171/amendpdf/0001H02.01H.pdf"
OPEN_TEXT = f"{HOST}/bills991/hlrbillspdf/9999H.01I.pdf"  # session 991 is in 2099: always open
WITNESS = f"{HOST}/bills171/witness/FORM.pdf"


def _pdf(texts: list[str]) -> bytes:
    """A minimal PDF with one page per text (hand-built so no PDF writer is needed)."""
    n = len(texts)
    kids = " ".join(f"{3 + 2 * i} 0 R" for i in range(n))
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", f"<< /Type /Pages /Kids [{kids}] /Count {n} >>".encode()]
    for i, text in enumerate(texts):
        objs.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] /Contents {4 + 2 * i} 0 R "
            "/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>".encode()
        )
        stream = f"BT /F1 12 Tf 20 50 Td ({text}) Tj ET".encode()
        objs.append(f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream")
    out = b"%PDF-1.4\n"
    offsets = []
    for i, body in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    return out + f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode()


PDF_A = _pdf(["Hello bill one"])
PDF_B = _pdf(["Second page one", "Second page two"])


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path / "cache")
    return tmp_path


def _table(name: str, columns: dict[str, str], rows: list[tuple]) -> None:
    folder = db.table_dir(name)
    cols = ", ".join(f"{k} {v}" for k, v in columns.items())
    with duckdb.connect() as con:
        con.execute(f"create table t ({cols})")
        for row in rows:
            con.execute(f"insert into t values ({', '.join('?' * len(row))})", list(row))
        con.execute(f"copy t to '{(folder / 'part-000-of-001.parquet').as_posix()}' (format parquet)")


@pytest.fixture
def links_landed(env):
    """The mo_house link tables for one closed session (171), one open one (991), and a witness table."""
    s = "varchar"
    _table(
        "mo_house_xml_bill_texts",
        {
            "session_code": s,
            "file_name": s,
            "text_index": "integer",
            "lr_number": s,
            "version_type_code": s,
            "text_link": s,
        },
        [
            ("171", "171-HB1.XML", 1, "0001H.01", "IN", TEXT_1),
            ("171", "171-HB2.XML", 1, "0002H.01", "IN", TEXT_2),
            ("991", "991-HB9.XML", 1, "9999H.01", "IN", OPEN_TEXT),
            ("171", "171-HB3.XML", 1, None, None, None),  # no link
            ("171", "171-HB4.XML", 1, None, None, "  "),  # blank link
        ],
    )
    _table(
        "mo_house_xml_bill_summaries",
        {
            "session_code": s,
            "file_name": s,
            "summary_index": "integer",
            "lr_number": s,
            "version_type_code": s,
            "summary_text_link": s,
        },
        [("171", "171-HB1.XML", 1, "0001H.01", "IN", SUMMARY), ("171", "171-HB1.XML", 2, "0001H.02", "CS", SUMMARY)],
    )
    _table(
        "mo_house_xml_bill_fiscal_notes",
        {"session_code": s, "file_name": s, "fiscal_note_index": "integer", "fiscal_note_link": s},
        [("171", "171-HB1.XML", 1, FISCAL), ("171", "171-HB1.XML", 2, DEAD)],
    )
    _table(
        "mo_house_xml_senate_act_amendments",
        {"session_code": s, "file_name": s, "amendment_index": "integer", "lr_number": s, "amendment_text": s},
        [("171", "171-SENATEACTLIST.XML", 1, "3329S24", AMEND)],
    )
    _table(
        "mo_house_xml_bill_witnesses",
        {"session_code": s, "file_name": s, "witness_index": "integer", "witness_forms_link": s},
        [("171", "171-HB1.XML", 1, WITNESS)],
    )


class Site:
    """A fake documents.house.mo.gov that counts the requests made to it."""

    def __init__(self, pages: dict[str, m.Fetched]):
        self.pages = pages
        self.requests: list[str] = []
        self.headers: dict[str, dict | None] = {}

    def __call__(self, url: str, headers: dict | None = None) -> m.Fetched:
        self.requests.append(url)
        self.headers[url] = headers
        return self.pages.get(url, m.Fetched(404, None, "text/html", "HTTP 404"))


def _pdf_ok(data: bytes) -> m.Fetched:
    return m.Fetched(200, data, "application/pdf", None)


def _site() -> Site:
    return Site(
        {
            TEXT_1: _pdf_ok(PDF_A),
            TEXT_2: _pdf_ok(PDF_B),
            OPEN_TEXT: _pdf_ok(PDF_A),
            SUMMARY: m.Fetched(200, b"<html>Not here</html>", "text/html", None),
            FISCAL: _pdf_ok(PDF_B),
            AMEND: _pdf_ok(PDF_A),
            DEAD: m.Fetched(None, None, None, "ConnectTimeout: timed out"),
        }
    )


def _rows(table: str, drop=("loaded_at", "checked_at")) -> list[dict]:
    with duckdb.connect() as con:
        cur = con.execute(f"select * from read_parquet('{db.raw_glob(table)}') order by url")
        names = [d[0] for d in cur.description]
        return [{k: v for k, v in zip(names, r, strict=True) if k not in drop} for r in cur.fetchall()]


def test_links_union_dedupes_urls_and_skips_blank_links(links_landed):
    found = {x.url: x for x in m.links(list(m.KINDS))}
    assert set(found) == {TEXT_1, TEXT_2, OPEN_TEXT, SUMMARY, FISCAL, DEAD, AMEND}  # no witness form, no blanks
    assert found[SUMMARY].n_links == 2 and found[SUMMARY].version_code == "IN"  # first link row wins
    assert found[AMEND].kind == "amendment" and found[AMEND].lr_number == "3329S24"  # Senate-act table is read
    assert found[FISCAL].lr_number is None
    assert [x.url for x in m.links(["fiscal_note"])] == sorted([FISCAL, DEAD])
    assert {x.url for x in m.links(list(m.KINDS), {"171"})} == set(found) - {OPEN_TEXT}


def test_shards_split_the_urls_stably_and_completely(links_landed):
    every = {x.url for x in m.links(list(m.KINDS))}
    parts = [{x.url for x in m.units(db.Shard(i, 3))} for i in range(3)]
    assert set().union(*parts) == every
    assert sum(len(p) for p in parts) == len(every)  # disjoint
    assert parts == [{x.url for x in m.units(db.Shard(i, 3))} for i in range(3)]
    assert parts[1] == {u for u in every if db.Shard(1, 3).owns(u)}  # decided by the URL alone


def test_pdfs_land_unchanged_and_errors_become_rows(links_landed, monkeypatch, env):
    site = _site()
    monkeypatch.setattr(m, "fetch_document", site)
    counts = m.load(db.UNSHARDED)
    assert counts == {"mo_house_pdf_files": 7, "mo_house_pdf_texts": 7, "mo_house_pdf_statute_refs": 0}
    raw = env / "raw"
    assert (raw / "mo_house_pdf/171/bill_text/0001H.01I.pdf").read_bytes() == PDF_A
    assert (raw / "mo_house_pdf/171/fiscal_note/0563-01N.ORG.pdf").read_bytes() == PDF_B
    assert not (raw / "mo_house_pdf/171/summary").exists()  # an HTML page served with 200 is not landed
    files = {r["url"]: r for r in _rows("mo_house_pdf_files")}
    assert files[TEXT_1]["size_bytes"] == len(PDF_A) and files[TEXT_1]["sha256"] == hashlib.sha256(PDF_A).hexdigest()
    assert files[TEXT_1]["rel_path"] == "mo_house_pdf/171/bill_text/0001H.01I.pdf" and files[TEXT_1]["error"] is None
    assert files[SUMMARY]["error"] == "not a PDF" and files[SUMMARY]["rel_path"] is None
    assert files[DEAD]["error"].startswith("ConnectTimeout") and files[DEAD]["http_status"] is None
    texts = {r["url"]: r for r in _rows("mo_house_pdf_texts")}
    assert texts[TEXT_2]["page_count"] == 2 and texts[TEXT_2]["text"] == "Second page one\nSecond page two"
    assert json.loads(texts[TEXT_2]["pages_json"]) == ["Second page one", "Second page two"]
    assert texts[TEXT_1]["lr_number"] == "0001H.01" and texts[TEXT_1]["version_code"] == "IN"
    assert texts[SUMMARY]["text"] is None and texts[SUMMARY]["error"] == "not a PDF" and texts[SUMMARY]["n_links"] == 2
    assert WITNESS not in site.requests


def test_bill_text_versions_get_statute_ref_rows_and_other_kinds_do_not(links_landed, monkeypatch):
    bill = _pdf(
        [
            "AN ACT To repeal sections 1.010 to 1.012, RSMo, and to enact in lieu thereof",
            "two new sections relating to x. Be it enacted by the General Assembly",
            "Section A. Sections 1.010 to 1.012, RSMo, are repealed and two new sections",
            "2 enacted in lieu thereof, to be known as sections 1.010 and 1.011, to read as",
            "3 follows:",
        ]
    )
    site = _site()
    site.pages[TEXT_1] = _pdf_ok(bill)
    site.pages[AMEND] = _pdf_ok(bill)  # same words in an amendment: not a bill text, no rows
    monkeypatch.setattr(m, "fetch_document", site)
    counts = m.load(db.UNSHARDED)
    assert counts["mo_house_pdf_statute_refs"] == 3
    rows = _rows("mo_house_pdf_statute_refs")
    assert [(r["action"], r["ordinal"], r["section_start"], r["section_end"]) for r in rows] == [
        ("repeal", 1, "1.010", "1.012"),
        ("enact", 1, "1.010", None),
        ("enact", 2, "1.011", None),
    ]
    assert {(r["url"], r["session_code"], r["file_name"], r["version_code"]) for r in rows} == {
        (TEXT_1, "171", "171-HB1.XML", "IN")
    }
    assert rows[0]["clause"] == "To repeal sections 1.010 to 1.012, RSMo, and"


def test_rerun_without_downloads_still_fills_the_statute_ref_rows(links_landed, monkeypatch):
    bill = _pdf(
        [
            "AN ACT To repeal section 1.010, RSMo, and to enact in lieu thereof one new section",
            "relating to x. Be it enacted by the General Assembly",
            "Section A. Section 1.010, RSMo, is repealed and one new section",
            "2 enacted in lieu thereof, to be known as section 1.010, to read as follows:",
        ]
    )
    site = _site()
    site.pages[TEXT_1] = _pdf_ok(bill)
    _run(monkeypatch, site)
    first = _rows("mo_house_pdf_statute_refs")
    assert len(first) == 2
    again = _site()
    again.pages[TEXT_1] = _pdf_ok(bill)
    _run(monkeypatch, again)
    assert TEXT_1 not in again.requests or again.requests.count(TEXT_1) == 0
    assert _rows("mo_house_pdf_statute_refs") == first


def test_second_run_of_closed_sessions_makes_no_requests_and_rewrites_nothing(links_landed, monkeypatch, env):
    monkeypatch.setattr(m, "fetch_document", _site())
    m.load(db.UNSHARDED)
    first_files, first_texts = _rows("mo_house_pdf_files"), _rows("mo_house_pdf_texts")

    def stamps():
        return {p: (p.stat().st_mtime_ns, p.stat().st_ino) for p in (env / "raw/mo_house_pdf").rglob("*.pdf")}

    landed = stamps()
    assert landed

    again = _site()
    monkeypatch.setattr(m, "fetch_document", again)
    monkeypatch.setattr(m, "_is_open", lambda code: code == "991")
    m.load(db.UNSHARDED)
    # reachable closed-session PDFs are not fetched again; a transient failure is retried, the permanent one
    # (HTML where a PDF belongs) is in the negative cache
    assert set(again.requests) == {DEAD}
    assert stamps() == landed
    assert _rows("mo_house_pdf_files") == first_files
    assert _rows("mo_house_pdf_texts") == first_texts


def test_open_session_is_rechecked_weekly_and_rewritten_only_on_change(links_landed, monkeypatch, env):
    link = next(x for x in m.links(["bill_text"]) if x.url == OPEN_TEXT)
    dest = env / "raw" / m.rel_path(link)
    site = _site()
    m.land(link, site)
    assert site.requests == [OPEN_TEXT]
    m.land(link, site)
    assert site.requests == [OPEN_TEXT]  # younger than a week
    old = time.time() - 8 * 86400
    os.utime(dest, (old, old))
    inode = dest.stat().st_ino
    m.land(link, site)
    assert site.requests == [OPEN_TEXT, OPEN_TEXT]
    assert dest.stat().st_ino == inode  # same bytes: the file is not replaced
    assert dest.stat().st_mtime > old + 86400  # re-checked, same bytes: touched, content untouched
    os.utime(dest, (old, old))
    site.pages[OPEN_TEXT] = _pdf_ok(PDF_B)
    row, data = m.land(link, site)
    assert dest.read_bytes() == PDF_B == data and row.sha256 == hashlib.sha256(PDF_B).hexdigest()


def test_failed_recheck_of_an_open_session_file_keeps_the_landed_pdf_and_its_text(links_landed, monkeypatch, env):
    monkeypatch.setattr(m, "fetch_document", _site())
    m.load(db.UNSHARDED)
    link = next(x for x in m.links(["bill_text"]) if x.url == OPEN_TEXT)
    dest = env / "raw" / m.rel_path(link)
    old = time.time() - 8 * 86400
    os.utime(dest, (old, old))
    stamp = (dest.stat().st_mtime_ns, dest.stat().st_ino)

    def timeout(url):
        return m.Fetched(None, None, None, "ReadTimeout: timed out")

    monkeypatch.setattr(m, "fetch_document", timeout)
    m.load(db.UNSHARDED)
    assert dest.read_bytes() == PDF_A and (dest.stat().st_mtime_ns, dest.stat().st_ino) == stamp
    file_row = next(r for r in _rows("mo_house_pdf_files") if r["url"] == OPEN_TEXT)
    assert file_row["error"] is None and file_row["sha256"] == hashlib.sha256(PDF_A).hexdigest()
    text_row = next(r for r in _rows("mo_house_pdf_texts") if r["url"] == OPEN_TEXT)
    assert text_row["text"] == "Hello bill one"  # text still there
    assert text_row["error"] is None

    for bad in (m.Fetched(404, None, "text/html", "HTTP 404"), m.Fetched(200, b"<html>x</html>", "text/html", None)):
        row, data = m.land(link, lambda url, bad=bad: bad)
        assert data == PDF_A and row.error is None and row.sha256 == hashlib.sha256(PDF_A).hexdigest()


def test_filtered_run_does_not_refetch_a_stale_open_session_file_outside_the_filter(links_landed, monkeypatch, env):
    link = next(x for x in m.links(["bill_text"]) if x.url == OPEN_TEXT)
    dest = env / "raw" / m.rel_path(link)
    site = _site()
    m.land(link, site)
    old = time.time() - 8 * 86400
    os.utime(dest, (old, old))
    site.requests.clear()
    row, data = m.land(link, site, fetch=False)
    assert site.requests == [] and data == PDF_A and row.error is None
    assert dest.stat().st_mtime == pytest.approx(old, abs=2)  # not even touched


def test_kinds_and_sessions_options_only_limit_fetching_and_pieces_add_up(links_landed, monkeypatch):
    site = _site()
    monkeypatch.setattr(m, "fetch_document", site)
    monkeypatch.setenv("MOGOV_HOUSE_PDF_KINDS", "bill_text")
    monkeypatch.setenv("MOGOV_HOUSE_PDF_SESSIONS", "171")
    m.load(db.UNSHARDED)
    assert sorted(site.requests) == sorted([TEXT_1, TEXT_2])
    assert {r["url"] for r in _rows("mo_house_pdf_files")} == {TEXT_1, TEXT_2}  # nothing else is on disk yet
    monkeypatch.setenv("MOGOV_HOUSE_PDF_KINDS", "amendment")  # the next piece keeps the bill texts' rows
    m.load(db.UNSHARDED)
    assert site.requests[2:] == [AMEND]
    assert {r["url"] for r in _rows("mo_house_pdf_texts")} == {TEXT_1, TEXT_2, AMEND}
    monkeypatch.setenv("MOGOV_HOUSE_PDF_KINDS", "witness")
    with pytest.raises(SystemExit):
        m.load(db.UNSHARDED)


def test_shards_land_disjoint_parts_that_add_up(links_landed, monkeypatch):
    site = _site()
    monkeypatch.setattr(m, "fetch_document", site)
    for i in range(2):
        m.load(db.Shard(i, 2))
    assert len(site.requests) == len(set(site.requests)) == 7  # no URL fetched by two shards
    assert len(_rows("mo_house_pdf_files")) == 7


def test_corrupt_pdf_is_an_error_row_not_a_failed_run():
    link = m.Link(TEXT_1, "bill_text", "171", "171-HB1.XML", None, None, 1)
    row = m.extract(link, b"%PDF-1.4 garbage", None)
    assert row.text is None and row.error


def test_fetch_document_reports_status_and_never_raises(monkeypatch):
    class Resp:
        def __init__(self, status):
            self.status_code, self.content, self.headers = status, b"x", {"content-type": "text/html"}

    answers = iter([Resp(503), Resp(404)])
    calls = []

    class Client:
        def get(self, url):
            calls.append(url)
            return next(answers)

    monkeypatch.setattr(m, "client", lambda: Client())
    monkeypatch.setattr(m.time, "sleep", lambda s: None)
    got = m.fetch_document(TEXT_1, interval=0)
    assert (got.status, got.error, got.content) == (404, "HTTP 404", None) and len(calls) == 2
    assert m.fetch_document("ftp://x/y.pdf").error == "not an http(s) URL"


def test_amendment_words_not_glued():
    """Real page 1 of 203 HB12 amendment 5794H02.11H: spaces are 3.0pt, the pdfplumber default x_tolerance, so the
    default glued them (#639). The loader's setting keeps the words apart; the old call (no x_tolerance) did not."""
    pdf = (Path(__file__).parent / "fixtures" / "mo_house_amendment_5794H02_11H_p1.pdf").read_bytes()
    text = pdftext.page_texts(pdf, layout=False, x_tolerance=m.X_TOLERANCE)[0]
    assert "AMEND House Committee Substitute for House Bill No. 12, Page 3," in text
    old = pdftext.page_texts(pdf, layout=False)[0]
    assert "AMENDHouse" in old and "AMEND House" not in old
    row = m.extract(m.Link(AMEND, "amendment", "171", "171-HB1.XML", None, None, 1), pdf, None)
    assert "AMEND House Committee Substitute" in row.text


def _run(monkeypatch, site):
    monkeypatch.setattr(m, "fetch_document", site)
    m.load(db.UNSHARDED)


def test_permanent_failures_of_closed_sessions_are_not_retried_until_the_negative_cache_expires(
    links_landed, monkeypatch
):
    _run(monkeypatch, _site())
    again = _site()
    _run(monkeypatch, again)
    assert SUMMARY not in again.requests  # 200-with-HTML: remembered as "not a PDF"
    assert DEAD in again.requests  # a timeout is transient
    row = next(r for r in _rows("mo_house_pdf_files") if r["url"] == SUMMARY)
    assert row["error"] == "not a PDF" and row["rel_path"] is None
    assert next(r for r in _rows("mo_house_pdf_texts") if r["url"] == SUMMARY)["error"] == "not a PDF"

    later = _site()
    real_now = m._now
    monkeypatch.setattr(m, "_now", lambda: real_now() + timedelta(seconds=m.NEGATIVE_CACHE_S + 60))
    _run(monkeypatch, later)
    assert SUMMARY in later.requests  # 30 days on, ask again


def test_404_is_permanent_but_429_5xx_and_open_sessions_are_retried(links_landed):
    link = next(x for x in m.links(["fiscal_note"]) if x.url == FISCAL)
    open_link = next(x for x in m.links(["bill_text"]) if x.url == OPEN_TEXT)
    for status, retried in ((404, False), (410, False), (429, True), (500, True), (408, True)):
        site = Site({FISCAL: m.Fetched(status, None, "text/html", f"HTTP {status}")})
        first, _ = m.land(
            link,
            site,
        )
        site.requests.clear()
        again, _ = m.land(link, site, prev=first)
        assert bool(site.requests) is retried, status
        assert again.error == f"HTTP {status}"
    site = Site({OPEN_TEXT: m.Fetched(404, None, "text/html", "HTTP 404")})
    first, _ = m.land(open_link, site)
    m.land(open_link, site, prev=first)
    assert len(site.requests) == 2  # an open session's missing document may be published later


def test_unchanged_files_are_not_read_again_and_their_text_comes_from_the_cache(links_landed, monkeypatch):
    _run(monkeypatch, _site())
    first = _rows("mo_house_pdf_texts")
    files = _rows("mo_house_pdf_files")

    def no_read(*args, **kwargs):
        raise AssertionError("a PDF was read or hashed again")

    real_read = Path.read_bytes
    monkeypatch.setattr(Path, "read_bytes", lambda self: no_read() if self.suffix == ".pdf" else real_read(self))
    monkeypatch.setattr(m, "_described", no_read)
    monkeypatch.setattr(pdftext, "page_texts", no_read)
    _run(monkeypatch, _site())
    assert _rows("mo_house_pdf_texts") == first
    assert [r for r in _rows("mo_house_pdf_files") if r["rel_path"]] == [r for r in files if r["rel_path"]]


def test_a_changed_file_is_read_again(links_landed, monkeypatch, env):
    _run(monkeypatch, _site())
    dest = env / "raw/mo_house_pdf/171/bill_text/0001H.01I.pdf"
    dest.write_bytes(PDF_B)  # same URL, different size and mtime
    _run(monkeypatch, _site())
    row = next(r for r in _rows("mo_house_pdf_files") if r["url"] == TEXT_1)
    assert row["sha256"] == hashlib.sha256(PDF_B).hexdigest()
    assert next(r for r in _rows("mo_house_pdf_texts") if r["url"] == TEXT_1)["page_count"] == 2


def test_open_session_recheck_is_conditional_and_a_304_keeps_file_row_and_text(links_landed, monkeypatch, env):
    site = _site()
    site.pages[OPEN_TEXT] = m.Fetched(200, PDF_A, "application/pdf", None, '"v1"', "Mon, 01 Jan 2099 00:00:00 GMT")
    _run(monkeypatch, site)
    dest = env / "raw/mo_house_pdf/991/bill_text/9999H.01I.pdf"
    assert next(r for r in _rows("mo_house_pdf_files") if r["url"] == OPEN_TEXT)["etag"] == '"v1"'
    old = time.time() - 8 * 86400
    os.utime(dest, (old, old))
    inode = dest.stat().st_ino
    again = _site()
    again.pages[OPEN_TEXT] = m.Fetched(304, None, None, None)
    _run(monkeypatch, again)
    assert again.headers[OPEN_TEXT] == {"If-None-Match": '"v1"', "If-Modified-Since": "Mon, 01 Jan 2099 00:00:00 GMT"}
    assert dest.read_bytes() == PDF_A and dest.stat().st_ino == inode and dest.stat().st_mtime > old + 86400
    row = next(r for r in _rows("mo_house_pdf_files") if r["url"] == OPEN_TEXT)
    assert row["error"] is None and row["sha256"] == hashlib.sha256(PDF_A).hexdigest() and row["etag"] == '"v1"'
    assert next(r for r in _rows("mo_house_pdf_texts") if r["url"] == OPEN_TEXT)["text"] == "Hello bill one"
    # a 200 with new bytes replaces the file and the validators
    os.utime(dest, (old, old))
    changed = _site()
    changed.pages[OPEN_TEXT] = m.Fetched(200, PDF_B, "application/pdf", None, '"v2"', None)
    _run(monkeypatch, changed)
    assert dest.read_bytes() == PDF_B
    row = next(r for r in _rows("mo_house_pdf_files") if r["url"] == OPEN_TEXT)
    assert row["etag"] == '"v2"' and row["sha256"] == hashlib.sha256(PDF_B).hexdigest()


def test_a_filtered_run_keeps_the_error_rows_of_earlier_pieces(links_landed, monkeypatch):
    _run(monkeypatch, _site())
    assert {SUMMARY, DEAD} <= {r["url"] for r in _rows("mo_house_pdf_files") if r["error"]}
    monkeypatch.setenv("MOGOV_HOUSE_PDF_KINDS", "amendment")
    again = _site()
    _run(monkeypatch, again)
    assert again.requests == []  # the amendment is on disk; nothing else is fetched
    files = {r["url"]: r for r in _rows("mo_house_pdf_files")}
    assert len(files) == 7 and files[SUMMARY]["error"] == "not a PDF" and files[DEAD]["error"].startswith("Connect")
    texts = {r["url"]: r for r in _rows("mo_house_pdf_texts")}
    assert len(texts) == 7 and texts[DEAD]["error"].startswith("Connect") and texts[TEXT_1]["text"]


def test_fetch_document_sends_validators_and_reports_304(monkeypatch):
    seen = []

    class Resp:
        status_code, content = 304, b""
        headers: ClassVar[dict] = {"etag": '"v1"'}

    class Client:
        def get(self, url, headers=None):
            seen.append(headers)
            return Resp()

    monkeypatch.setattr(m, "client", lambda: Client())
    got = m.fetch_document(TEXT_1, interval=0, headers={"If-None-Match": '"v1"'})
    assert seen == [{"If-None-Match": '"v1"'}]
    assert (got.status, got.content, got.error, got.etag) == (304, None, None, '"v1"')


def test_a_file_rewritten_at_the_same_size_with_a_new_mtime_is_read_again(links_landed, monkeypatch, env):
    _run(monkeypatch, _site())
    dest = env / "raw/mo_house_pdf/171/bill_text/0001H.01I.pdf"
    other = PDF_A.replace(b"Hello", b"Jello")
    assert len(other) == len(PDF_A)
    old = dest.stat().st_mtime
    dest.write_bytes(other)
    os.utime(dest, (old + 3600, old + 3600))
    _run(monkeypatch, _site())
    row = next(r for r in _rows("mo_house_pdf_files") if r["url"] == TEXT_1)
    assert row["sha256"] == hashlib.sha256(other).hexdigest()
    assert "Jello" in next(r for r in _rows("mo_house_pdf_texts") if r["url"] == TEXT_1)["text"]


def test_an_extraction_timeout_is_not_retried_until_the_negative_cache_expires(links_landed, monkeypatch):
    real = pdftext.page_texts
    calls: list[int] = []

    def slow(data, **kw):
        if data == PDF_B:
            calls.append(1)
            raise pdftext.ExtractTimeout("ran past 600 s")
        return real(data, **kw)

    monkeypatch.setattr(pdftext, "page_texts", slow)
    _run(monkeypatch, _site())
    first = len(calls)
    assert first >= 1
    row = next(r for r in _rows("mo_house_pdf_texts") if r["url"] == TEXT_2)
    assert "ExtractTimeout" in row["error"] and row["text"] is None  # (cached) if another URL had the same bytes
    _run(monkeypatch, _site())
    assert len(calls) == first  # remembered by hash: not extracted again
    assert next(r for r in _rows("mo_house_pdf_texts") if r["url"] == TEXT_2)["error"] == (
        row["error"] if row["error"].startswith(m.CACHED) else m.CACHED + row["error"]
    )
    assert next(r for r in _rows("mo_house_pdf_files") if r["url"] == TEXT_2)["error"] is None  # file row stays good
    # past the window the document is tried again
    monkeypatch.setattr(m, "NEGATIVE_CACHE_S", -1)
    _run(monkeypatch, _site())
    assert len(calls) > first


def _timing_out(calls):
    real = pdftext.page_texts

    def slow(data, **kw):
        if data == PDF_B:
            calls.append(1)
            raise pdftext.ExtractTimeout("ran past 600 s")
        return real(data, **kw)

    return slow


def test_an_unwritable_timeout_marker_does_not_fail_the_run(links_landed, monkeypatch):
    monkeypatch.setattr(pdftext, "page_texts", _timing_out([]))

    real_write = m.write_atomic

    def broken(path, content):
        if "mo_house_pdf_timeouts" in str(path):
            raise OSError("disk full")
        real_write(path, content)

    monkeypatch.setattr(m, "write_atomic", broken)
    _run(monkeypatch, _site())
    row = next(r for r in _rows("mo_house_pdf_texts") if r["url"] == TEXT_2)
    assert row["error"].startswith("ExtractTimeout") and row["text"] is None


def test_an_extractor_upgrade_retries_a_remembered_timeout(links_landed, monkeypatch):
    calls: list[int] = []
    monkeypatch.setattr(pdftext, "page_texts", _timing_out(calls))
    _run(monkeypatch, _site())
    first = len(calls)
    monkeypatch.setattr(pdftext, "EXTRACTOR", "pdfplumber-99.0")
    _run(monkeypatch, _site())
    assert len(calls) > first


def test_a_remembered_timeout_is_reported_as_cached_without_reading_the_file(links_landed, monkeypatch):
    calls: list[int] = []
    monkeypatch.setattr(pdftext, "page_texts", _timing_out(calls))
    _run(monkeypatch, _site())
    row = next(r for r in m.previous_files().values() if r.url == TEXT_2)
    link = next(x for x in m.links(list(m.KINDS)) if x.url == TEXT_2)

    def no_read(self):
        raise AssertionError("file was read")

    monkeypatch.setattr(m.Path, "read_bytes", no_read)
    got = m.extract_landed(link, row)
    assert got.error.startswith("(cached) ExtractTimeout")
    # the in-extract check, with the bytes in hand
    assert m.extract(link, PDF_B, None).error.startswith("(cached) ExtractTimeout")
    assert len(calls) == 1


def _doc_part(name: str, rows: list[tuple]) -> None:
    folder = db.table_dir(m.DocFile.TABLE)
    cols = "url varchar, kind varchar, session_code varchar, error varchar, landed_at timestamp, checked_at timestamp"
    with duckdb.connect() as con:
        con.execute(f"create table t ({cols})")
        for row in rows:
            con.execute("insert into t values (?, 'bill_text', '171', ?, ?, ?)", list(row))
        con.execute(f"copy t to '{(folder / name).as_posix()}' (format parquet)")


def test_previous_files_keeps_the_newest_row_and_breaks_ties_by_part_name(env):
    old, new = datetime(2026, 1, 1), datetime(2026, 6, 1)
    _doc_part("part-000-of-002.parquet", [("u-newer", "from-low-part", None, new), ("u-tie", "low", None, None)])
    _doc_part("part-001-of-002.parquet", [("u-newer", "from-high-part", None, old), ("u-tie", "high", None, None)])
    got = m.previous_files()
    assert got["u-newer"].error == "from-low-part"  # newest checked_at wins even in the lower-named part
    assert got["u-tie"].error == "high"  # both NULL: the higher-named part wins, deterministically


def test_previous_files_falls_back_to_landed_at_when_checked_at_is_null(env):
    old, new = datetime(2026, 1, 1), datetime(2026, 6, 1)
    _doc_part("part-000-of-002.parquet", [("u", "newer-landed", new, None)])
    _doc_part("part-001-of-002.parquet", [("u", "older-checked", None, old)])
    assert m.previous_files()["u"].error == "newer-landed"


def test_links_counts_a_link_row_once_while_two_shard_counts_coexist(links_landed):
    before = {x.url: x.n_links for x in m.links(list(m.KINDS))}
    folder = db.table_dir("mo_house_xml_bill_texts")
    (folder / "part-001-of-002.parquet").write_bytes((folder / "part-000-of-001.parquet").read_bytes())
    assert {x.url: x.n_links for x in m.links(list(m.KINDS))} == before


def test_only_rows_fetched_this_run_log_failures(links_landed, monkeypatch):
    _run(monkeypatch, _site())
    logged: list[str] = []
    monkeypatch.setattr(m.log, "warning", lambda event, **kw: logged.append(kw.get("url")))
    _run(monkeypatch, _site())
    assert logged == [DEAD]  # SUMMARY is negative-cached (carried over) and stays quiet; DEAD was asked again


def test_previous_files_retries_when_a_part_vanishes_mid_read(links_landed, monkeypatch):
    _run(monkeypatch, _site())
    real = m._read_previous_files
    calls = []

    def flaky():
        calls.append(1)
        if len(calls) == 1:
            raise duckdb.IOException("No files found that match the pattern")
        return real()

    monkeypatch.setattr(m, "_read_previous_files", flaky)
    monkeypatch.setattr(m.time, "sleep", lambda s: None)
    assert TEXT_1 in m.previous_files()
    assert len(calls) == 2
