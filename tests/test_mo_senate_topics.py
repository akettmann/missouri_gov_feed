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


def _card(href, label, description, sponsors=""):
    return f"""
    <div class="card card--with-footer">
      <div class="card__header"><span><a {href}>{label}</a></span></div>
      <div class="card__body">{description}</div>
      <div class="card__footer">{sponsors}</div>
    </div>"""


def _section(keyword, *cards):
    return (
        '<div class="card collapsible"><div class="card__header">'
        f'<span class="heading--label">{keyword}</span><span class="status-chip">{len(cards)}</span></div>'
        f'<div class="card__body">{"".join(cards)}</div></div>'
    )


def test_tricky_markup():
    page = (
        "<html><body>"
        '<h1><span class="heading--label">Page title</span></h1>'
        + _section(
            "Taxes &amp; <i>Fees</i>",
            # attributes in the other order, extra class tokens, nested tags, entities, odd whitespace
            _card(
                'class="x bill-number-color y" href="https://e.org/b?a=1&amp;b=2"',
                "\n  SB\u00a0<b>1</b>\n",
                '<p style="m">Modifies   <em>taxes</em>\n and &quot;fees&quot; &#x27;now&#x27;</p><p>second</p>',
                '<a target="_blank" class="sponsor-item" href="https://e.org/s?id=1&amp;x=2">'
                "\n Sponsor: <span>Jane  Doe</span> </a>"
                '<a class="sponsor-item" href="/s?id=2">Sponsor: Al Roe</a>',
            ),
            # no sponsors, and a description-less card must not borrow the next card's paragraph
            _card('href="/b2" class="bill-number-color"', "HB 2", "<div>no paragraph</div>"),
            _card('href="/b3" class="bill-number-color"', "HB 3", "<p>third</p>", '<a class="other" href="/z">z</a>'),
        )
        + _section("Zoning", _card('href="/b4" class="bill-number-color"', "SB 4", "<p>fourth</p>"))
        + "</body></html>"
    )
    rows = parse_index(page)
    assert rows == [
        {
            "keyword": "Taxes & Fees",
            "bill_label": "SB 1",
            "bill_url": "https://e.org/b?a=1&b=2",
            "description": "Modifies taxes and \"fees\" 'now'",
            "sponsors": [
                {"name": "Jane Doe", "url": "https://e.org/s?id=1&x=2"},
                {"name": "Al Roe", "url": "/s?id=2"},
            ],
        },
        {"keyword": "Taxes & Fees", "bill_label": "HB 2", "bill_url": "/b2", "description": "", "sponsors": []},
        {"keyword": "Taxes & Fees", "bill_label": "HB 3", "bill_url": "/b3", "description": "third", "sponsors": []},
        {"keyword": "Zoning", "bill_label": "SB 4", "bill_url": "/b4", "description": "fourth", "sponsors": []},
    ]


def test_empty_page_has_no_rows():
    assert parse_index("<html><body><p>No results</p></body></html>") == []
