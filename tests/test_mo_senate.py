import io
from collections import Counter
from pathlib import Path

import pdfplumber

from mogov.loaders.mo_senate import parse_journal

FIXTURE = Path(__file__).parent / "fixtures" / "senate_journal_2025_day05.pdf"


def _text() -> str:
    with pdfplumber.open(io.BytesIO(FIXTURE.read_bytes())) as pdf:
        return "\n".join(p.extract_text() or "" for p in pdf.pages)


# Two blocks from the 2022 journal RDay6005052296-2344.pdf, as pdfplumber extracts them
BLOCKS_2022 = """On motion of Senator O'Laughlin, HB 2485 was read the 3rd time and passed by the following vote:
YEAS—Senators
Bean Beck Bernskoetter Brattin Brown Burlison Cierpiot
Crawford Eslinger Gannon Hoskins Hough Koenig Luetkemeyer
May O'Laughlin Onder Razer Riddle Rizzo Roberts
Rowden Schatz Thompson Rehder Washington White Wieland Williams—28
NAYS—Senators
Arthur Moon Mosley Schupp—4
Absent—Senators—None
Absent with leave—Senator Eigel—1
Journal of the Senate 2308
Excused from voting—Senator Hegeman—1
Vacancies—None
The emergency clause was adopted by the following vote:
YEAS—Senators
Bean Bernskoetter Brattin Brown Burlison Cierpiot Crawford
Eslinger Hegeman Hoskins Hough Koenig Luetkemeyer O'Laughlin
Onder Riddle Rowden Schatz Thompson Rehder White Wieland—21
NAYS—Senators
Arthur Beck May Moon Mosley Razer Rizzo
Roberts Schupp Washington Williams—11
Journal of the Senate 2310
Absent—Senators—None
Absent with leave—Senators—2
Eigel Gannon
Vacancies—None
"""


def test_every_seat_is_accounted_for_once():
    rows = parse_journal(BLOCKS_2022)
    for block in (0, 1):
        names = [r["name"] for r in rows if r["block_index"] == block]
        assert len(names) == len(set(names)) == 34, block
    assert "Thompson Rehder" in {r["name"] for r in rows}
    assert not {"Thompson", "Rehder", "Vacancies"} & {r["name"] for r in rows}


def test_excused_and_leading_totals():
    rows = parse_journal(BLOCKS_2022)
    excused = [r for r in rows if r["category"] == "Excused from voting"]
    assert [(r["block_index"], r["name"], r["declared_count"]) for r in excused] == [(0, "Hegeman", 1)]
    leave = [r for r in rows if r["block_index"] == 1 and r["category"] == "Absent with leave"]
    assert [(r["name"], r["declared_count"]) for r in leave] == [("Eigel", 2), ("Gannon", 2)]


def test_veto_session_journal_date():
    header = "Journal of the Senate\nFIRST REGULAR SESSION\nVETO SESSION\nWEDNESDAY, SEPTEMBER 15, 2021\n"
    rows = parse_journal(header + BLOCKS_2022)
    assert {(r["journal_day"], r["journal_date"]) for r in rows} == {("VETO SESSION", "SEPTEMBER 15, 2021")}


def test_run_together_names_are_split():
    text = BLOCKS_2022.replace("Rowden Schatz", "RowdenSchatz").replace("May O'Laughlin", "May McCreery O'Laughlin")
    names = {r["name"] for r in parse_journal(text) if r["block_index"] == 0}
    assert {"Rowden", "Schatz", "McCreery"} <= names and "RowdenSchatz" not in names


def test_cut_off_heading_word_is_not_a_senator():
    text = BLOCKS_2022.replace("Absent with leave—Senator Eigel—1", "Absent with leave—Senato Eigel—1")
    names = {r["name"] for r in parse_journal(text) if r["block_index"] == 0}
    assert "Senato" not in names and "Eigel" in names


def test_vote_blocks_parse_and_counts_match_declared_totals():
    rows = parse_journal(_text())
    assert rows, "expected at least one recorded vote"
    first = [r for r in rows if r["block_index"] == 0]
    cats = Counter(r["category"] for r in first)
    assert cats["YEAS"] == 33
    assert cats["Absent with leave"] == 1
    assert {"Brown (16)", "Brown (26)", "Gregory (15)", "O'Laughlin"} <= {r["name"] for r in first}
    assert "SR 19 was adopted" in first[0]["context"]
    assert first[0]["journal_date"] == "JANUARY 15, 2025"
    # every block: tokens per category equal the printed "—N" total
    for (block, cat), n in Counter((r["block_index"], r["category"]) for r in rows).items():
        declared = next(r["declared_count"] for r in rows if r["block_index"] == block and r["category"] == cat)
        assert declared is None or declared == n, (block, cat, n, declared)


def test_vacancy_count_lands_on_every_row_of_its_block():
    rows = parse_journal(BLOCKS_2022)
    assert {r["vacancies"] for r in rows} == {0}
    # "Vacancies—None" is zero; a printed number is that many
    text = BLOCKS_2022.replace("Vacancies—None", "Vacancies—1", 1)
    rows = parse_journal(text)
    assert {r["vacancies"] for r in rows if r["block_index"] == 0} == {1}
    assert {r["vacancies"] for r in rows if r["block_index"] == 1} == {0}


def test_vacancy_count_forms():
    base = BLOCKS_2022
    for printed, expected in [("Vacancies—Senator—2", 2), ("Vacancies-3", 3), ("Vacancies—None", 0)]:
        rows = parse_journal(base.replace("Vacancies—None", printed, 1))
        assert {r["vacancies"] for r in rows if r["block_index"] == 0} == {expected}, printed


# 2024+ order: "Excused from voting" is printed AFTER "Vacancies", possibly past a page header
EXCUSED_AFTER_VACANCIES = """HB 1 was read the 3rd time and passed by the following vote:
YEAS—Senators
Bean Beck Bernskoetter Brattin Brown Burlison Cierpiot
Crawford Eslinger Gannon Hoskins Hough Koenig Luetkemeyer
May O'Laughlin Onder Razer Riddle Rizzo Roberts
Rowden Schatz Thompson Rehder Washington White Wieland—27
NAYS—Senators
Arthur Moon Mosley Schupp—4
Absent—Senators—None
Absent with leave—Senators—2
Eigel Gannon
Vacancies—None
Journal of the Senate 2308
Excused from voting—Senator Williams—1
"""


def test_excused_printed_after_vacancies_is_kept():
    rows = parse_journal(EXCUSED_AFTER_VACANCIES)
    excused = [r for r in rows if r["category"] == "Excused from voting"]
    assert [(r["name"], r["declared_count"], r["vacancies"]) for r in excused] == [("Williams", 1, 0)]


def test_vacancies_reads_the_first_token_only():
    base = BLOCKS_2022
    assert {r["vacancies"] for r in parse_journal(base) if r["block_index"] == 0} == {0}
    text = base.replace("Vacancies—None", "Vacancies—None 5", 1)
    assert {r["vacancies"] for r in parse_journal(text) if r["block_index"] == 0} == {0}


def test_excused_after_vacancies_past_an_odd_page_header():
    # odd pages print "<page> <Day> - <Weekday>, <date>" (digits first), mixed case, with a plain hyphen
    text = EXCUSED_AFTER_VACANCIES.replace(
        "Journal of the Senate 2308", "623 Forty-Fourth Day - Thursday, April 4, 2024"
    )
    rows = parse_journal(text)
    excused = [r for r in rows if r["category"] == "Excused from voting"]
    assert [(r["name"], r["declared_count"], r["vacancies"]) for r in excused] == [("Williams", 1, 0)]
