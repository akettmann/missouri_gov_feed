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
        return LIST_2025_R if params["session"] == "R" else LIST_2025_EMPTY

    monkeypatch.setattr(m, "_get", fake_get)
    assert len(bills) == 5
    counts = m.load(shard)
    rows = {}
    for table in (m.BILLS_TABLE, m.ACTIONS_TABLE):
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
        return LIST_2025_R if params["session"] == "R" else LIST_2025_EMPTY

    monkeypatch.setattr(m, "_get", fake_get)
    counts = m.load(db.Shard())
    assert counts == {m.BILLS_TABLE: 5, m.ACTIONS_TABLE: 0}
    assert sum(1 for p in requests if p.get("handler") == "Actions") == 5
    assert [p["session"] for p in requests if "session" in p] == ["R", "E1"]


def test_empty_regular_session_does_not_hide_an_extraordinary_one(monkeypatch):
    pages = {"R": LIST_2025_EMPTY, "E1": LIST_2025_R, "E2": LIST_2025_EMPTY}
    monkeypatch.setattr(m, "_get", lambda params, year, **kw: pages[params["session"]])
    assert [s for s, _ in m.session_lists(2025)] == ["E1"]
