import json
from collections import Counter
from datetime import datetime
from pathlib import Path

import pytest

from mogov import db
from mogov.loaders import mo_senate_bills as m

FIXTURES = Path(__file__).parent / "fixtures"


def _read(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


# the 2025 regular session's bill list cut to five real bills (SB 1, SB 2, SB 600, SJR 1, SR 18); the page's
# bill cards are left out, they are not parsed
LIST_2025_R = _read("senate_bills_list_2025_R_excerpt.html")
LIST_2025_EMPTY = _read("senate_bills_list_2025_E_empty.html")  # session=E: a real page with `const bills = [];`
SB1_ACTIONS = _read("senate_bills_actions_2025_sb1.html")  # a long history, through the governor's signature
SB600_ACTIONS = _read("senate_bills_actions_2025_sb600.html")  # died in committee


def test_bill_list_rows_are_the_embedded_json_unchanged():
    bills = m.parse_bill_list(LIST_2025_R)
    assert [(b["billPrefix"], b["billSuffix"], b["billId"]) for b in bills] == [
        ("SB", 1, 233),
        ("SB", 2, 234),
        ("SR", 18, 2146392),
        ("SJR", 1, 73),
        ("SB", 600, 2724185),
    ]
    sb1 = bills[0]
    assert sb1["sponsorLastName"] == "Crawford" and sb1["session"] == "R" and sb1["year"] == 2025
    assert sb1["houseAmendmentsUrl"] == "https://www.house.mo.gov/amendments.aspx?bill=SB1&year=2025&code=R"
    assert sb1["mainBillUrl"].endswith("BillInformation?year=2025&billid=233")
    # resolutions have no handler: the keys are simply absent, nothing is invented
    assert "handlerLastName" not in bills[2]


def test_page_without_bills_gives_no_rows():
    assert m.parse_bill_list(LIST_2025_EMPTY) == []
    assert m.parse_bill_list("<html><body><script>var bills = 1;</script></body></html>") == []
    assert m.parse_bill_list("") == []


def test_bills_array_is_read_by_a_json_parser_not_cut_at_a_bracket():
    page = (
        '<html><body><script>const bills = [{"billId": 1, "briefDescription": "a ]; b", "n": [1, 2]}];'
        " const other = [9];</script></body></html>"
    )
    assert m.parse_bill_list(page) == [{"billId": 1, "briefDescription": "a ]; b", "n": [1, 2]}]


def test_long_action_history_in_served_order():
    actions = m.parse_actions(SB1_ACTIONS)
    assert [a["action_index"] for a in actions] == list(range(len(actions)))
    assert len(actions) > 10
    # newest first, as served
    assert actions[0] == {
        "action_index": 0,
        "action_date": "05/13/2025",
        "action": "Signed by Governor",
        "journal_ref": "S1760-1761",
        "journal_url": "https://www.senate.mo.gov/25info/pdf-jrnl/DAY68.pdf#page=32",
    }
    dates = [datetime.strptime(a["action_date"], "%m/%d/%Y") for a in actions]
    assert dates == sorted(dates, reverse=True)
    assert all(a["action"] for a in actions)
    # a House-side reference keeps both chamber references as printed
    assert any("H" in a["journal_ref"] and "/" in a["journal_ref"] for a in actions)


def test_short_action_history():
    assert m.parse_actions(SB600_ACTIONS) == [
        {
            "action_index": 0,
            "action_date": "03/13/2025",
            "action": "Second Read and Referred S Government Efficiency Committee",
            "journal_ref": "S625",
            "journal_url": "https://www.senate.mo.gov/25info/pdf-jrnl/DAY37.pdf#page=12",
        },
        {
            "action_index": 1,
            "action_date": "01/21/2025",
            "action": "S First Read",
            "journal_ref": "S151",
            "journal_url": "https://www.senate.mo.gov/25info/pdf-jrnl/DAY07.pdf#page=3",
        },
    ]


def test_actions_fragment_without_a_table_gives_no_rows():
    assert m.parse_actions("") == []
    assert m.parse_actions("\n  \n") == []
    assert m.parse_actions('<div class="actions-container"><p>No actions</p></div>') == []


def test_action_without_a_journal_link():
    fragment = (
        '<div id="actionsTable"><table><tbody><tr><td>01/07/2026</td><td>Prefiled</td><td></td></tr>'
        "<tr><td>junk</td></tr></tbody></table></div>"
    )
    assert m.parse_actions(fragment) == [
        {"action_index": 0, "action_date": "01/07/2026", "action": "Prefiled", "journal_ref": "", "journal_url": None}
    ]


def _lists():
    bills = m.parse_bill_list(LIST_2025_R)
    extra = [{"billId": 18267452, "billPrefix": "SB", "billSuffix": 1, "session": "E1"}]
    # 2025 SB 1 (id 233) and the special session's SB 1 are different bills
    return [(2025, "R", bills), (2025, "E1", extra), (2024, "R", [{"billId": n} for n in range(1000, 1400)])]


@pytest.mark.parametrize("count", [1, 2, 3, 4, 7])
def test_shards_cover_every_bill_exactly_once(count):
    lists = _lists()
    everything = [(y, s, b["billId"]) for y, s, bills in lists for b in bills]
    owned = [[(y, s, b["billId"]) for y, s, b in m.owned_bills(db.Shard(i, count), lists)] for i in range(count)]
    assert sorted(x for shard in owned for x in shard) == sorted(everything)
    if count > 1:
        assert all(owned)  # 405 bills: no shard is left empty


def test_split_is_stable_and_independent_of_listing_order():
    lists = _lists()
    reordered = [(y, s, list(reversed(b))) for y, s, b in reversed(lists)]
    for i in range(4):
        first = {(y, s, b["billId"]) for y, s, b in m.owned_bills(db.Shard(i, 4), lists)}
        again = {(y, s, b["billId"]) for y, s, b in m.owned_bills(db.Shard(i, 4), lists)}
        other_order = {(y, s, b["billId"]) for y, s, b in m.owned_bills(db.Shard(i, 4), reordered)}
        assert first == again == other_order


def test_a_bill_listed_twice_is_one_unit():
    dup = {"billId": 233, "billPrefix": "SB", "billSuffix": 1}
    assert len(m.owned_bills(db.Shard(), [(2025, "R", [dup, dup])])) == 1


def test_session_lists_probe_extraordinary_sessions_until_one_is_empty(monkeypatch):
    asked = []
    pages = {
        "R": LIST_2025_R,
        "E1": LIST_2025_R,
        "E2": LIST_2025_EMPTY,
    }

    def fake_get(params, year, **kw):
        asked.append(params["session"])
        return pages[params["session"]]

    monkeypatch.setattr(m, "_get", fake_get)
    found = m.session_lists(2025)
    assert [s for s, _ in found] == ["R", "E1"]
    assert asked == ["R", "E1", "E2"]


def test_list_page_check_rejects_a_page_without_the_bills_array():
    class Resp:
        url = "https://www.senate.mo.gov/BillTracking/Bills/BillList"
        content = b"<html>Service unavailable</html>"

    with pytest.raises(m.NotABillList):
        m._is_bill_list(Resp)
    Resp.content = LIST_2025_EMPTY.encode()
    m._is_bill_list(Resp)  # an empty list is a real answer


def _run(monkeypatch, tmp_path, shard, requests):
    """Run load() against canned pages; returns the landed rows by table."""
    raw = tmp_path / "raw"
    monkeypatch.setattr(db, "RAW_DIR", raw)
    monkeypatch.setattr(m, "window_years", lambda: [2025])
    bills = m.parse_bill_list(LIST_2025_R)

    def fake_get(params, year, **kw):
        requests.append(tuple(sorted(params.items())))
        if params.get("handler") == "Actions":
            return SB600_ACTIONS if params["billId"] == 2724185 else SB1_ACTIONS
        if params.get("handler"):
            return _doc_page(params)
        return LIST_2025_R if params["session"] == "R" else LIST_2025_EMPTY

    monkeypatch.setattr(m, "_get", fake_get)
    assert len(bills) == 5
    counts = m.load(shard)
    rows = {}
    for table in (m.BILLS_TABLE, m.ACTIONS_TABLE, *m.DOC_TABLES):
        with db.connect() as con:
            files = db.raw_glob(table)
            rows[table] = con.execute(f"select record_key, payload from read_parquet('{files}')").fetchall()
    return counts, rows


def test_load_lands_each_bill_once_across_shards_and_rerun_is_identical(monkeypatch, tmp_path):
    requests: list = []
    landed = []
    for i in range(3):
        counts, rows = _run(monkeypatch, tmp_path, db.Shard(i, 3), requests)
        landed.append(counts)
    # after all three shards: one list row per bill, action rows keyed per bill and index
    _, rows = _run(monkeypatch, tmp_path, db.Shard(2, 3), requests)
    assert sum(c[m.BILLS_TABLE] for c in landed) == 5
    keys = [k for k, _ in rows[m.BILLS_TABLE]]
    assert sorted(keys) == sorted({k for k in keys}) and len(keys) == 5
    assert Counter(json.loads(p)["session_type"] for _, p in rows[m.BILLS_TABLE]) == {"R": 5}
    sb600 = [json.loads(p) for k, p in rows[m.ACTIONS_TABLE] if k.startswith("2025/R/2724185/")]
    assert [a["action"] for a in sorted(sb600, key=lambda a: a["action_index"])] == [
        "Second Read and Referred S Government Efficiency Committee",
        "S First Read",
    ]
    assert sb600[0]["bill"] == "SB600" and sb600[0]["bill_id"] == 2724185 and sb600[0]["session_type"] == "R"

    # idempotent: running a shard again replaces its part with identical rows
    first = sorted(rows[m.ACTIONS_TABLE])
    _run(monkeypatch, tmp_path, db.Shard(2, 3), requests)
    _, again = _run(monkeypatch, tmp_path, db.Shard(2, 3), requests)
    assert sorted(again[m.ACTIONS_TABLE]) == first


def test_load_fetches_each_owned_bill_actions_once_and_survives_an_empty_history(monkeypatch, tmp_path):
    requests: list = []
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(m, "window_years", lambda: [2025])

    def fake_get(params, year, **kw):
        requests.append(params)
        if params.get("handler") == "Actions":
            return ""  # the site answered with nothing for this bill
        if params.get("handler"):
            return _doc_page(params)
        return LIST_2025_R if params["session"] == "R" else LIST_2025_EMPTY

    monkeypatch.setattr(m, "_get", fake_get)
    counts = m.load(db.Shard())
    # SB 1: 3 texts, 3 fiscal notes, 1 amendment, 4 summaries; the other four bills: 1 text + 1 summary each
    assert counts == {
        m.BILLS_TABLE: 5,
        m.ACTIONS_TABLE: 0,
        m.TEXTS_TABLE: 3 + 4,
        m.FISCAL_NOTES_TABLE: 3,
        m.AMENDMENTS_TABLE: 1,
        m.SUMMARIES_TABLE: 4 + 4,
    }
    assert sum(1 for p in requests if p.get("handler") == "Actions") == 5
    # one request per bill and tab: 5 x (Actions + the four tabs)
    assert Counter(p["handler"] for p in requests if "handler" in p) == {
        h: 5 for h in ("Actions", "BillText", "FiscalNotes", "Amendments", "Summaries")
    }
    assert [p["session"] for p in requests if "session" in p] == ["R", "E1"]


def test_empty_regular_session_does_not_hide_an_extraordinary_one(monkeypatch):
    pages = {"R": LIST_2025_EMPTY, "E1": LIST_2025_R, "E2": LIST_2025_EMPTY}
    monkeypatch.setattr(m, "_get", lambda params, year, **kw: pages[params["session"]])
    assert [s for s, _ in m.session_lists(2025)] == ["E1"]


# --- the bill page's document tabs (#587): trimmed real fragments of 2025 SB 1 (passed) and SB 600 (died)
SB1_TEXT = _read("senate_bills_text_2025_sb1.html")
SB600_TEXT = _read("senate_bills_text_2025_sb600.html")
SB1_FISCAL = _read("senate_bills_fiscal_notes_2025_sb1.html")
NO_FISCAL = _read("senate_bills_fiscal_notes_2025_sb600_none.html")
SB1_AMENDMENTS = _read("senate_bills_amendments_2025_sb1.html")
NO_AMENDMENTS = _read("senate_bills_amendments_2025_sb600_none.html")
SB1_SUMMARIES = _read("senate_bills_summaries_2025_sb1.html")
SB600_SUMMARIES = _read("senate_bills_summaries_2025_sb600.html")


def test_text_versions_in_served_order_with_lr_number_and_version():
    texts = m.parse_texts(SB1_TEXT)
    assert [t["doc_index"] for t in texts] == [0, 1, 2]
    assert texts[0] == {
        "doc_index": 0,
        "url": "https://www.senate.mo.gov/25info/pdf-bill/tat/SB1.pdf",
        "title": "SB 1 - 0453S.04T",
        "label": "0453S.04T - Truly Agreed to and Finally Passed",
        "lr_number": "0453S.04T",
        "version": "Truly Agreed to and Finally Passed",
    }
    assert [t["version"] for t in texts] == ["Truly Agreed to and Finally Passed", "Perfected", "Introduced"]
    assert [t["url"].split("/")[-2] for t in texts] == ["tat", "perf", "intro"]


def test_one_text_version_and_a_label_without_a_dash():
    assert [t["label"] for t in m.parse_texts(SB600_TEXT)] == ["2302S.01I - Introduced"]
    fragment = '<div class="link-card-stack"><a href="https://x/y.pdf" title="t">Introduced</a></div>'
    assert m.parse_texts(fragment) == [
        {
            "doc_index": 0,
            "url": "https://x/y.pdf",
            "title": "t",
            "label": "Introduced",
            "lr_number": None,
            "version": "Introduced",
        }
    ]


def test_fiscal_notes_in_served_order():
    notes = m.parse_fiscal_notes(SB1_FISCAL)
    assert notes[0] == {
        "doc_index": 0,
        "url": "https://www.senate.mo.gov/FiscalNotes/2025-1/0453S.04T.ORG.pdf",
        "title": "Fiscal Note - 0453S.04T.ORG",
        "label": "Truly Agreed to and Finally Passed (0453S.04T.ORG)",
    }
    assert [n["label"].split("(")[0].strip() for n in notes] == [
        "Truly Agreed to and Finally Passed",
        "Perfected",
        "Introduced",
    ]


def test_amendment_with_its_status_chip_and_pdf_id():
    assert m.parse_amendments(SB1_AMENDMENTS) == [
        {
            "doc_index": 0,
            "amendment_id": 3,
            "url": "https://www.senate.mo.gov/BillTracking/Bills/BillInformation?handler=AmendmentPdf&year=2025&amendmentId=3",
            "title": "2/4/2025 - SS S offered & adopted (Crawford)--(0453S.04F)",
            "label": "2/4/2025 - SS S offered & adopted (Crawford)--(0453S.04F)",
            "status": "2/4/2025 - Adopted",
        }
    ]


def test_summaries_keep_their_text_as_printed():
    summaries = m.parse_summaries(SB1_SUMMARIES)
    assert [s["summary_id"] for s in summaries] == [12475046, 566841, 566551, 275676]
    assert [s["doc_index"] for s in summaries] == [0, 1, 2, 3]
    assert summaries[0]["label"] == "Truly Agreed to and Finally Passed"
    # tabs and CR LF line breaks are the site's, kept; entities are decoded
    assert summaries[0]["text"].startswith("\tSS/SB 1 - This act amends sections of law")
    only = m.parse_summaries(SB600_SUMMARIES)
    assert len(only) == 1 and only[0]["label"] == "Introduced"
    assert only[0]["text"] == (
        "\tSB 600 - This act repeals the requirement that the Governor's appointments of commissioners to the "
        "Bi-State Development Agency be selected from panels of three nominees selected by the Mayor of the City "
        "of St. Louis and the County Executive of St. Louis County.\r\nERIC VANDER WEERD"
    )


def test_fragments_with_no_documents_give_no_rows():
    assert m.parse_fiscal_notes(NO_FISCAL) == []
    assert m.parse_amendments(NO_AMENDMENTS) == []
    for parse in (m.parse_texts, m.parse_fiscal_notes, m.parse_amendments, m.parse_summaries):
        assert parse("") == []
        assert parse("  \n") == []
    assert m.parse_summaries('<div class="summaries-container"><div id="summariesContent"></div></div>') == []


class _Resp:
    url = "https://www.senate.mo.gov/BillTracking/Bills/BillList?handler=x"

    def __init__(self, body: str):
        self.content = body.encode()


@pytest.mark.parametrize(
    ("handler", "good"),
    [
        ("BillText", SB1_TEXT),
        ("FiscalNotes", SB1_FISCAL),
        ("FiscalNotes", NO_FISCAL),
        ("Amendments", SB1_AMENDMENTS),
        ("Amendments", NO_AMENDMENTS),
        ("Summaries", SB600_SUMMARIES),
    ],
)
def test_fragment_check_accepts_real_answers_including_none_available(handler, good):
    m._is_doc_fragment(handler)(_Resp(good))


@pytest.mark.parametrize("handler", list(m.DOC_HANDLERS))
@pytest.mark.parametrize(
    "bad",
    ["<html><body>Service unavailable</body></html>", "", "<h1>Access denied</h1>", SB1_ACTIONS],
)
def test_fragment_check_rejects_error_and_block_pages(handler, bad):
    with pytest.raises(m.NotABillFragment):
        m._is_doc_fragment(handler)(_Resp(bad))


def test_a_block_page_is_not_cached_and_a_real_one_is(monkeypatch, tmp_path):
    """Through the real fetch(): the rejected body leaves no cache file, the accepted one does."""
    import httpx

    from mogov import http

    monkeypatch.setattr(http, "CACHE_DIR", tmp_path / "cache")
    served = {"body": "<html>blocked</html>"}

    def handler(request):
        return httpx.Response(200, content=served["body"].encode())

    monkeypatch.setattr(http, "client", lambda: httpx.Client(transport=httpx.MockTransport(handler)))
    check = m._is_doc_fragment("Amendments")
    params = {"handler": "Amendments"}
    with pytest.raises(m.NotABillFragment):
        http.fetch(m.LIST_URL, params, check=check)
    assert not http._cache_path(m.LIST_URL, params).exists()
    served["body"] = NO_AMENDMENTS
    assert http.fetch(m.LIST_URL, params, check=check) == NO_AMENDMENTS.encode()
    assert http._cache_path(m.LIST_URL, params).exists()


def _doc_page(params):
    """The canned answer of a document tab: SB 1 has them, every other bill has none of its own."""
    sb1 = params["billId"] == 233
    return {
        "BillText": SB1_TEXT if sb1 else SB600_TEXT,
        "FiscalNotes": SB1_FISCAL if sb1 else NO_FISCAL,
        "Amendments": SB1_AMENDMENTS if sb1 else NO_AMENDMENTS,
        "Summaries": SB1_SUMMARIES if sb1 else SB600_SUMMARIES,
    }[params["handler"]]


def _landed(table):
    with db.connect() as con:
        files = db.raw_glob(table)
        return {
            k: json.loads(p)
            for k, p in con.execute(f"select record_key, payload from read_parquet('{files}')").fetchall()
        }


def test_document_rows_land_with_the_bills_shard_and_keys_and_rerun_identically(monkeypatch, tmp_path):
    requests: list = []
    for i in range(3):
        _run(monkeypatch, tmp_path, db.Shard(i, 3), requests)
    texts = _landed(m.TEXTS_TABLE)
    assert sorted(k for k in texts if k.startswith("2025/R/233/")) == ["2025/R/233/0", "2025/R/233/1", "2025/R/233/2"]
    assert texts["2025/R/233/1"] == {
        "year": 2025,
        "session_type": "R",
        "bill_id": 233,
        "bill": "SB1",
        "doc_index": 1,
        "url": "https://www.senate.mo.gov/25info/pdf-bill/perf/SB1.pdf",
        "title": "SB 1 - 0453S.04P",
        "label": "0453S.04P - Perfected",
        "lr_number": "0453S.04P",
        "version": "Perfected",
    }
    # a bill's rows in every table sit in the part of the shard that owns it
    for table in (m.BILLS_TABLE, m.ACTIONS_TABLE, *m.DOC_TABLES):
        for key in _landed(table):
            bill_key = "/".join(key.split("/")[:3]) if table != m.BILLS_TABLE else key
            assert db.Shard(0, 3).owns(bill_key) + db.Shard(1, 3).owns(bill_key) + db.Shard(2, 3).owns(bill_key) == 1
    amendments = _landed(m.AMENDMENTS_TABLE)
    assert list(amendments) == ["2025/R/233/0"] and amendments["2025/R/233/0"]["amendment_id"] == 3
    before = {t: _landed(t) for t in m.DOC_TABLES}
    _run(monkeypatch, tmp_path, db.Shard(1, 3), requests)
    assert {t: _landed(t) for t in m.DOC_TABLES} == before


def test_fiscal_notes_request_carries_the_session_type_and_other_tabs_do_not():
    bill = {"billId": 233, "billPrefix": "SB", "billSuffix": 1}
    assert m._doc_params(2025, "R", bill, "FiscalNotes") == {
        "billId": 233,
        "year": 2025,
        "billPrefix": "SB",
        "billSuffix": 1,
        "handler": "FiscalNotes",
        "sessionType": "R",
    }
    assert "sessionType" not in m._doc_params(2025, "R", bill, "BillText")


def test_documents_can_be_skipped(monkeypatch, tmp_path):
    monkeypatch.setenv("MOGOV_SENATE_BILL_DOCS", "0")
    requests: list = []
    counts = _run_without_doc_tables(monkeypatch, tmp_path, requests)
    assert set(counts) == {m.BILLS_TABLE, m.ACTIONS_TABLE}  # the document tables keep their earlier landing
    assert counts[m.BILLS_TABLE] == 5 and counts[m.ACTIONS_TABLE] > 0
    assert {p["handler"] for p in requests if "handler" in p} == {"Actions"}


def _run_without_doc_tables(monkeypatch, tmp_path, requests):
    monkeypatch.setattr(db, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(m, "window_years", lambda: [2025])

    def fake_get(params, year, **kw):
        requests.append(params)
        if params.get("handler") == "Actions":
            return SB1_ACTIONS
        return LIST_2025_R if params["session"] == "R" else LIST_2025_EMPTY

    monkeypatch.setattr(m, "_get", fake_get)
    return m.load(db.Shard())


def test_text_label_splits_at_the_first_dash_only():
    fragment = (
        '<div class="link-card-stack"><a href="https://x/y.pdf" title="t">1234S.01I - Introduced - as amended</a></div>'
    )
    row = m.parse_texts(fragment)[0]
    assert (row["lr_number"], row["version"]) == ("1234S.01I", "Introduced - as amended")


def test_many_amendments_keep_order_ids_and_every_status():
    amendments = m.parse_amendments(_read("senate_bills_amendments_2025_sb4.html"))
    assert [a["doc_index"] for a in amendments] == list(range(8))
    ids = [a["amendment_id"] for a in amendments]
    assert all(isinstance(i, int) for i in ids) and len(set(ids)) == 8
    assert [a["status"] for a in amendments][:5] == [
        "2/19/2025 - Withdrawn",
        "2/19/2025 - Moot",
        "2/20/2025 - Adopted, as amended",
        "2/19/2025 - Adopted",
        "2/19/2025 - Defeated",
    ]
    assert amendments[0]["label"] == "2/4/2025 - SS S offered (Cierpiot)--(0120S.04F)"
    # the title is as served (two spaces); the label has its whitespace collapsed
    adopted = amendments[3]
    assert adopted["title"] == "2/19/2025 - SA 1 to SS#2 S offered  & adopted (Trent)--(0120S08.09S)"
    assert adopted["label"] == "2/19/2025 - SA 1 to SS#2 S offered & adopted (Trent)--(0120S08.09S)"
