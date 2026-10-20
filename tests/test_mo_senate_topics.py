from collections import Counter
from pathlib import Path

from mogov.loaders.mo_senate_topics import parse_index

# the 2020 regular session's topical index, cut after its first two keywords (Abortion, Accountants)
FIXTURE = Path(__file__).parent / "fixtures" / "senate_topics_2020_excerpt.html"


def test_cards_parse_under_their_keyword():
    rows = parse_index(FIXTURE.read_text(encoding="utf-8"))
    # the page title is styled like a keyword heading but has no cards
    assert Counter(r["keyword"] for r in rows) == {"Abortion": 8, "Accountants": 5}
    sb703 = next(r for r in rows if r["bill_label"] == "SB 703")
    assert sb703 == {
        "keyword": "Accountants",
        "bill_label": "SB 703",
        "bill_url": "https://www.senate.mo.gov/BillTracking/Bills/BillInformation?year=2020&billid=26838019",
        "description": "Modifies provisions relating to the practice of public accounting",
        "sponsors": [{"name": "Denny Hoskins", "url": "https://www.senate.mo.gov/Senators/PastSenators?id=14"}],
    }
    # House bills that reached the Senate are indexed too, linked to house.mo.gov
    hb = next(r for r in rows if r["bill_label"].startswith("HB"))
    assert hb["bill_label"] == "HB 2046" and hb["bill_url"].startswith(
        "https://www.House.mo.gov/bill.aspx?bill=HB2046&"
    )
    assert all(r["sponsors"] for r in rows)
