from collections import Counter
from pathlib import Path

from mogov.loaders.mo_house import _parse_rollcall_pdf, _probe_day, _rollcall_url

FIXTURE = Path(__file__).parent / "fixtures" / "house_rollcall_251_048_010.pdf"
MISS = b"<!DOCTYPE html><html>error</html>"


def _site(*numbers: int):
    """A fake fetch for day 71 of session 251 that has roll calls with these numbers."""
    pdfs = {_rollcall_url("251", 71, n) for n in numbers}

    def get(url: str) -> bytes:
        return b"%PDF-1.4 " + url.encode() if url in pdfs else MISS

    return get


def _numbers(results) -> list[int]:
    return [int(url.rsplit(".", 2)[-2]) for url, _ in results]


def test_probe_day_finds_roll_calls_the_xml_does_not_link():
    results = list(_probe_day("251", 71, {2}, _site(1, 2, 3, 4)))
    assert _numbers(results) == [1, 2, 3, 4]
    assert results[0][0] == "https://documents.house.mo.gov/billtracking/bills251/rollcalls/071.001.pdf"
    assert all(isinstance(data, bytes) for _, data in results)


def test_probe_day_keeps_going_through_gaps_below_the_highest_linked_number():
    results = list(_probe_day("251", 71, {5}, _site(1, 2, 4, 5, 6)))
    assert _numbers(results) == [1, 2, 4, 5, 6]


def test_probe_day_reports_a_missing_linked_roll_call():
    results = dict(_probe_day("251", 71, {2}, _site(1)))
    assert isinstance(results[_rollcall_url("251", 71, 2)], ValueError)


def test_probe_day_without_roll_calls_costs_one_request():
    calls = []

    def get(url: str) -> bytes:
        calls.append(url)
        return MISS

    assert list(_probe_day("251", 71, set(), get)) == []
    assert len(calls) == 1


def test_rollcall_pdf_tokens_match_printed_totals():
    header, votes = _parse_rollcall_pdf(FIXTURE.read_bytes())
    assert header["session_day"] == "48"
    assert header["rollcall_number"] == "10"
    assert header["vote_date"] == "4/3/2025"
    counts = Counter(code for code, _ in votes)
    assert counts["Y"] == int(header["totals"]["Yes"]) == 138
    assert counts["N"] == int(header["totals"]["No"]) == 15
    assert counts["P"] == int(header["totals"]["Present"]) == 1
    assert counts["@"] == int(header["totals"]["Absent"]) == 8
    names = {name for _, name in votes}
    assert {"BROWN 149", "FOUNTAIN HENDERS", "MR SPEAKER", "WALSH MOORE", "SMITH 46"} <= names


def test_open_session_also_lands_its_session_list(monkeypatch):
    """The open regular session has no zip, so its SessionList (the House's session names) is fetched directly;
    without it the newest session would have no name in dim_house_session."""
    from mogov.loaders import mo_house

    asked = []

    def fake_fetch(url, **_):
        asked.append(url.rsplit("/", 1)[-1])
        return b"<SessionList></SessionList>" if "List" in url else b"<html>no zip</html>"

    monkeypatch.setattr(mo_house, "fetch", fake_fetch)
    files = {name for name, _, _ in mo_house._session_files("261", 9999)}  # a year that is never past
    assert "261-SESSIONLIST.XML" in files


def test_open_session_dedupes_a_bill_the_billlist_links_twice(monkeypatch):
    """The House BillList repeats HR1/HR2 in odd-year sessions; each file must be yielded (and landed) once."""
    from mogov.loaders import mo_house

    link = "https://documents.house.mo.gov/xml/251-HR1.XML"
    lists = {
        "251-BillList.XML": f"<BillList><BillXML><BillXMLLink>{link}</BillXMLLink></BillXML>"
        f"<BillXML><BillXMLLink>{link}</BillXMLLink></BillXML>"
        "<BillXML><BillXMLLink>https://documents.house.mo.gov/xml/251-HB1.XML</BillXMLLink></BillXML></BillList>",
    }

    def fake_fetch(url, **_):
        name = url.rsplit("/", 1)[-1]
        if name in lists:
            return lists[name].encode()
        if name.upper().endswith(("-HR1.XML", "-HB1.XML")):
            return b"<R><BillInformation/></R>"
        return b"<html>no zip</html>"

    monkeypatch.setattr(mo_house, "fetch", fake_fetch)
    names = [name for name, _, _ in mo_house._session_files("251", 9999)]
    assert sorted(n for n in names if "HR1" in n or "HB1" in n) == ["251-HB1.XML", "251-HR1.XML"]
    assert len(names) == len(set(names))


def test_every_xml_in_the_zip_is_landed_including_unparsed_kinds(tmp_path, monkeypatch):
    """GRP* files are not parsed but the raw XML is kept unchanged like every other file."""
    import io
    import zipfile

    import duckdb

    from mogov import db
    from mogov.loaders import mo_house
    from mogov.parsers import mo_house as parser

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("191-HB1.xml", "<R><BillInformation><BillNumber>HB1</BillNumber></BillInformation></R>")
        zf.writestr("191-GRP1.xml", "<R><BillInformation><BillNumber>GRP1</BillNumber></BillInformation></R>")
    zip_bytes = buf.getvalue()
    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    monkeypatch.setattr(mo_house, "window_years", lambda: [2019])
    monkeypatch.setattr(mo_house, "fetch", lambda url, **_: zip_bytes if url.endswith("/191.zip") else b"<html/>")
    monkeypatch.setattr(mo_house, "_probe_day", lambda *a, **k: iter(()))
    mo_house.load(db.UNSHARDED)
    rows = duckdb.sql(
        f"select file_name, kind, path from read_parquet('{db.raw_glob(parser.XmlFile.TABLE)}') order by 1"
    ).fetchall()
    assert rows == [
        ("191-GRP1.XML", "other", "mo_house_xml/191/191-GRP1.XML.gz"),
        ("191-HB1.XML", "bill", "mo_house_xml/191/191-HB1.XML.gz"),
    ]
    assert (tmp_path / "mo_house_xml/191/191-GRP1.XML.gz").exists()
    bills = duckdb.sql(f"select bill from read_parquet('{db.raw_glob(parser.Bill.TABLE)}')").fetchall()
    assert bills == [("HB1",)]  # GRP1 stays out of the parser


def test_rollcall_extract_timeout_lands_as_an_error_row_and_the_run_goes_on(tmp_path, monkeypatch):
    import json

    import duckdb

    from mogov import db
    from mogov.loaders import mo_house

    def slow(data, **_):
        raise mo_house.pdftext.ExtractTimeout("text extraction ran past 1 s after 3 pages")

    def probe(code, day, linked, get):
        if code == "191" and day == 1:
            yield "https://x/r1.pdf", b"%PDF-a"
            yield "https://x/r2.pdf", b"%PDF-b"

    monkeypatch.setattr(db, "RAW_DIR", tmp_path)
    monkeypatch.setattr(mo_house, "window_years", lambda: [2019])
    monkeypatch.setattr(mo_house, "DAYS_IF_UNKNOWN", 1)
    import io
    import zipfile

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("191-HB1.xml", "<R><BillInformation><BillNumber>HB1</BillNumber></BillInformation></R>")
    zip_bytes = buf.getvalue()
    monkeypatch.setattr(mo_house, "fetch", lambda url, **_: zip_bytes if url.endswith("/191.zip") else b"<html/>")
    monkeypatch.setattr(mo_house, "_probe_day", probe)
    monkeypatch.setattr(mo_house.pdftext, "page_texts", slow)
    mo_house.load(db.UNSHARDED)
    rows = duckdb.sql(f"select payload from read_parquet('{db.raw_glob('mo_house_rollcalls')}')").fetchall()
    payloads = sorted((json.loads(p) for (p,) in rows), key=lambda p: p["url"])
    assert [p["url"] for p in payloads] == ["https://x/r1.pdf", "https://x/r2.pdf"]
    assert all("ran past" in p["error"] for p in payloads)
