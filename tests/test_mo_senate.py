import io
from collections import Counter
from pathlib import Path

import pdfplumber

from mogov.loaders.mo_senate import parse_journal

FIXTURE = Path(__file__).parent / "fixtures" / "senate_journal_2025_day05.pdf"


def _text() -> str:
    with pdfplumber.open(io.BytesIO(FIXTURE.read_bytes())) as pdf:
        return "\n".join(p.extract_text() or "" for p in pdf.pages)


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
