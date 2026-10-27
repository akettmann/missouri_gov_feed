import hashlib
import json
import os
import time

import duckdb
import pytest

from mogov import db, pdftext
from mogov.loaders import mo_house_docs as m

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

    def __call__(self, url: str) -> m.Fetched:
        self.requests.append(url)
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


def _rows(table: str, drop=("loaded_at",)) -> list[dict]:
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
    parts = [{x.url for x in m.units(list(m.KINDS), None, db.Shard(i, 3))} for i in range(3)]
    assert set().union(*parts) == every
    assert sum(len(p) for p in parts) == len(every)  # disjoint
    assert parts == [{x.url for x in m.units(list(m.KINDS), None, db.Shard(i, 3))} for i in range(3)]
    assert parts[1] == {u for u in every if db.Shard(1, 3).owns(u)}  # decided by the URL alone


def test_pdfs_land_unchanged_and_errors_become_rows(links_landed, monkeypatch, env):
    site = _site()
    monkeypatch.setattr(m, "fetch_document", site)
    counts = m.load(db.UNSHARDED)
    assert counts == {"mo_house_doc_files": 7, "mo_house_doc_texts": 7}
    raw = env / "raw"
    assert (raw / "mo_house_docs/171/bill_text/0001H.01I.pdf").read_bytes() == PDF_A
    assert (raw / "mo_house_docs/171/fiscal_note/0563-01N.ORG.pdf").read_bytes() == PDF_B
    assert not (raw / "mo_house_docs/171/summary").exists()  # an HTML page served with 200 is not landed
    files = {r["url"]: r for r in _rows("mo_house_doc_files")}
    assert files[TEXT_1]["size_bytes"] == len(PDF_A) and files[TEXT_1]["sha256"] == hashlib.sha256(PDF_A).hexdigest()
    assert files[TEXT_1]["rel_path"] == "mo_house_docs/171/bill_text/0001H.01I.pdf" and files[TEXT_1]["error"] is None
    assert files[SUMMARY]["error"] == "not a PDF" and files[SUMMARY]["rel_path"] is None
    assert files[DEAD]["error"].startswith("ConnectTimeout") and files[DEAD]["http_status"] is None
    texts = {r["url"]: r for r in _rows("mo_house_doc_texts")}
    assert texts[TEXT_2]["page_count"] == 2 and texts[TEXT_2]["text"] == "Second page one\nSecond page two"
    assert json.loads(texts[TEXT_2]["pages_json"]) == ["Second page one", "Second page two"]
    assert texts[TEXT_1]["lr_number"] == "0001H.01" and texts[TEXT_1]["version_code"] == "IN"
    assert texts[SUMMARY]["text"] is None and texts[SUMMARY]["error"] == "not a PDF" and texts[SUMMARY]["n_links"] == 2
    assert WITNESS not in site.requests


def test_second_run_of_closed_sessions_makes_no_requests_and_rewrites_nothing(links_landed, monkeypatch, env):
    monkeypatch.setattr(m, "fetch_document", _site())
    m.load(db.UNSHARDED)
    first_files, first_texts = _rows("mo_house_doc_files"), _rows("mo_house_doc_texts")

    def stamps():
        return {p: (p.stat().st_mtime_ns, p.stat().st_ino) for p in (env / "raw/mo_house_docs").rglob("*.pdf")}

    landed = stamps()
    assert landed

    again = _site()
    monkeypatch.setattr(m, "fetch_document", again)
    monkeypatch.setattr(m, "_is_open", lambda code: code == "991")
    m.load(db.UNSHARDED)
    # reachable closed-session PDFs are not fetched again; only the failures (no file to reuse) are retried
    assert set(again.requests) == {SUMMARY, DEAD}
    assert stamps() == landed
    assert _rows("mo_house_doc_files") == first_files
    assert _rows("mo_house_doc_texts") == first_texts


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


def test_kinds_and_sessions_options_narrow_the_run(links_landed, monkeypatch):
    site = _site()
    monkeypatch.setattr(m, "fetch_document", site)
    monkeypatch.setenv("MOGOV_HOUSE_DOCS_KINDS", "bill_text")
    monkeypatch.setenv("MOGOV_HOUSE_DOCS_SESSIONS", "171")
    m.load(db.UNSHARDED)
    assert sorted(site.requests) == sorted([TEXT_1, TEXT_2])
    monkeypatch.setenv("MOGOV_HOUSE_DOCS_KINDS", "witness")
    with pytest.raises(SystemExit):
        m.load(db.UNSHARDED)


def test_shards_land_disjoint_parts_that_add_up(links_landed, monkeypatch):
    site = _site()
    monkeypatch.setattr(m, "fetch_document", site)
    for i in range(2):
        m.load(db.Shard(i, 2))
    assert len(site.requests) == len(set(site.requests)) == 7  # no URL fetched by two shards
    assert len(_rows("mo_house_doc_files")) == 7


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
