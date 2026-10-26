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
