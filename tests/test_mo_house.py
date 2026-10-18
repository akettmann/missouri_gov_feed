from collections import Counter
from pathlib import Path

from mogov.loaders.mo_house import _parse_rollcall_pdf

FIXTURE = Path(__file__).parent / "fixtures" / "house_rollcall_251_048_010.pdf"


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
