from pathlib import Path

from mogov.loaders.mo_revisor import parse_chapter, parse_repeals, parse_section, parse_toc

FIXTURES = Path(__file__).parent / "fixtures" / "mo_revisor"


def read(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def test_toc_lists_chapters_under_their_title():
    # home page cut after its first two titles
    rows = parse_toc(read("home_excerpt.html"))
    assert [r["chapter"] for r in rows] == ["1", "2", "3", "7", "8", "9", "10", "11", "12", "14"]
    assert rows[0] == {
        "title": "I LAWS AND STATUTES",
        "chapter": "1",
        "chapter_name": "Laws in Force and Construction of Statutes",
    }
    assert rows[-1]["title"] == "II SOVEREIGNTY, JURISDICTION AND EMBLEMS"


def test_chapter_lists_each_section_version_once():
    versions = parse_chapter(read("chapter_1.html"))
    assert len(versions) == 54
    assert versions[:2] == [("1.010", 42), ("1.016", 51044)]
    # four-digit section numbers exist (1.1001-1.1010), so a section ID isn't always NNN.NNN
    assert ("1.1001", 57722) in versions


def test_section_text_heading_and_history():
    s = parse_section(read("section_1.010.html"))
    assert s["title_line"] == "Title I LAWS AND STATUTES"
    assert s["effective"] == "Effective - 28 Aug 2015, 2 histories"
    assert not s["historical"]
    assert s["heading"].startswith("1.010. Common law in force")
    assert s["paragraphs"][0].startswith(s["heading"] + " 1. The common law of England")
    assert s["paragraphs"][1].startswith("2. The general assembly expressly excludes")
    assert s["footnotes"][0] == "(RSMo 1939 § 645, A.L. 1957 p. 587, A.L. 2015 S.B. 239)"
    assert s["html"].startswith('<div style="margin:.1em 0em .4em .5em;">')
    assert "<form" not in s["html"]


def test_future_effective_version():
    s = parse_section(read("section_27.117_bid60727.html"))
    assert s["effective"] == "Effective - 01 Jul 2027, 2 histories, see footnote"
    assert s["footnotes"][0] == "(L. 2026 H.B. 2273, et al. merged with H.B. 2637 & 3155 merged with S.B. 999)"


def test_tables_keep_their_rows():
    s = parse_section(read("section_28.160.html"))
    table = s["paragraphs"][1]
    assert table.splitlines()[0] == "For issuing commission to notary public\t$15.00"
    assert s["paragraphs"][2].startswith("2. There is hereby established")
    assert not any(p.strip("\xad ") == "" for p in s["paragraphs"])


def test_repeals_and_transfers():
    rows = parse_repeals(read("rx_excerpt.html"))
    assert rows[0] == {
        "kind": "repealed",
        "section": "1.022",
        "bid": 36218,
        "note": "(Repealed L. 1975 H.B. 945 § 1)",
        "date": "9/28/1975",
    }
    assert [r["kind"] for r in rows] == ["repealed"] * 3 + ["transferred"] * 2
    assert rows[3]["note"] == "(Transferred 1959; now 442.560 )"
