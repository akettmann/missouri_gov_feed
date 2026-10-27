from mogov.parsers.mo_house_statute_refs import parse_statute_refs

HEAD = "SECOND REGULAR SESSION\nHOUSE BILL NO. 1\n103RD GENERAL ASSEMBLY\n1234H.01I JOSEPH ENGLER, Chief Clerk\n"
ENACTING = "Be it enacted by the General Assembly of the state of Missouri, as follows:\n"


def _bill(title: str, section_a: str) -> str:
    return f"{HEAD}AN ACT\n{title}\n{ENACTING}{section_a}\n1.010. The text of the section.\n"


def _short(refs):
    return [(r.action, r.ordinal, r.section_start, r.section_end, r.supp_year) for r in refs]


def test_repeal_and_enact_with_line_numbers_in_section_a():
    text = _bill(
        "To repeal sections 573.010 and 573.550, RSMo, and to enact in lieu thereof seven new\n"
        "sections relating to digital media, with penalty provisions.",
        "Section A. Sections 573.010 and 573.550, RSMo, are repealed and seven new\n"
        "2 sections enacted in lieu thereof, to be known as sections 407.3007, 407.3475, 537.039,\n"
        "3 537.043, 573.010, 573.550, and 573.570, to read as follows:",
    )
    refs = parse_statute_refs(text)
    assert _short(refs) == [
        ("repeal", 1, "573.010", None, None),
        ("repeal", 2, "573.550", None, None),
        ("enact", 1, "407.3007", None, None),
        ("enact", 2, "407.3475", None, None),
        ("enact", 3, "537.039", None, None),
        ("enact", 4, "537.043", None, None),
        ("enact", 5, "573.010", None, None),
        ("enact", 6, "573.550", None, None),
        ("enact", 7, "573.570", None, None),
    ]
    assert refs[0].clause.startswith("To repeal sections 573.010 and 573.550, RSMo,")
    assert "relating to" not in refs[0].clause


def test_single_section_has_no_range():
    text = _bill(
        "To repeal section 1.010, RSMo, and to enact in lieu thereof one new section relating to x.",
        "Section A. Section 1.010, RSMo, is repealed and one new section enacted in lieu thereof, to be known as\n"
        "2 section 1.010, to read as follows:",
    )
    assert _short(parse_statute_refs(text)) == [("repeal", 1, "1.010", None, None), ("enact", 1, "1.010", None, None)]


def test_range_is_kept_as_written():
    text = _bill(
        "To repeal sections 1.010 to 1.050, 2.020 and 135.1150 to 135.1160, RSMo, and to enact in lieu thereof\n"
        "new sections relating to x.",
        "Section A. Sections 1.010 to 1.050, RSMo, are repealed and new sections enacted in lieu thereof, to be\n"
        "2 known as sections 1.010 to 1.012 and 1.020, to read as follows:",
    )
    assert _short(parse_statute_refs(text)) == [
        ("repeal", 1, "1.010", "1.050", None),
        ("repeal", 2, "2.020", None, None),
        ("repeal", 3, "135.1150", "135.1160", None),
        ("enact", 1, "1.010", "1.012", None),
        ("enact", 2, "1.020", None, None),
    ]


def test_suffixed_and_uniform_code_ids():
    text = _bill(
        "To repeal sections 30A.010, 67.1360, 143.121 and 400.3-505, RSMo, and to enact in lieu thereof four new\n"
        "sections relating to x.",
        "Section A. Sections 30A.010, RSMo, are repealed and four new sections enacted in lieu thereof, to be known\n"
        "2 as sections 30A.010, 67.1360, 143.121 and 400.3-505, to read as follows:",
    )
    assert [r.section_start for r in parse_statute_refs(text) if r.action == "repeal"] == [
        "30A.010",
        "67.1360",
        "143.121",
        "400.3-505",
    ]


def test_supplement_year_applies_to_the_sections_before_that_rsmo():
    text = _bill(
        "To repeal sections 1.010 and 2.020, RSMo, and section 21.790, RSMo Supp. 2023, and sections 3.030 and\n"
        "3.040, RSMo Supp. 2024, as enacted by house bill no. 1, one hundred second general assembly, and to enact\n"
        "in lieu thereof four new sections relating to x.",
        "Section A. Sections 1.010 and 2.020, RSMo, are repealed and four new sections enacted in lieu thereof, to\n"
        "2 be known as sections 1.010, to read as follows:",
    )
    assert _short(parse_statute_refs(text))[:5] == [
        ("repeal", 1, "1.010", None, None),
        ("repeal", 2, "2.020", None, None),
        ("repeal", 3, "21.790", None, 2023),
        ("repeal", 4, "3.030", None, 2024),
        ("repeal", 5, "3.040", None, 2024),
    ]


def test_enact_only_chapter_amendment():
    text = _bill(
        "To amend chapter 161, RSMo, by adding thereto one new section relating to media literacy.",
        "Section A. Chapter 161, RSMo, is amended by adding thereto one new section, to be\n"
        "2 known as section 161.355, to read as follows:",
    )
    assert _short(parse_statute_refs(text)) == [("enact", 1, "161.355", None, None)]


def test_amend_section_title():
    text = _bill(
        "To amend section 1.010, RSMo, by adding thereto one new subsection relating to x.",
        "Section A. Section 1.010, RSMo, is amended by adding thereto one new subsection, to be known as\n"
        "2 subsection 3, to read as follows:",
    )
    assert _short(parse_statute_refs(text)) == [("amend", 1, "1.010", None, None)]


def test_to_read_as_follows_split_by_a_line_number():
    text = _bill(
        "To repeal section 68.010, RSMo, and to enact in lieu thereof one new section relating to x.",
        "Section A. Section 68.010, RSMo, is repealed and one new section enacted in lieu thereof, to be known as\n"
        "2 section 68.010, to read as\n3 follows:",
    )
    assert [r.action for r in parse_statute_refs(text)] == ["repeal", "enact"]


def test_no_rsmo_reference():
    appropriation = _bill(
        "To appropriate money for the expenses of the Office of Administration, to be expended only as provided in\n"
        "Article IV, Section 28 of the Constitution of Missouri, for the period beginning July 1, 2025.",
        "Section 2.005. To the Office of Administration\n2 For the Office, 1,000.\n",
    )
    resolution = (
        f"{HEAD}JOINT RESOLUTION\nSubmitting to the qualified voters of Missouri an amendment repealing Section 30(a)\n"
        "of Article IV of the Constitution of Missouri.\nBe it resolved by the House of Representatives, the Senate\n"
        "concurring therein:\nSection A. Section 30(a), Article IV, Constitution of Missouri, is repealed."
    )
    conveyance = _bill(
        "To authorize the conveyance of certain state property.", "Section 1. The department is authorized."
    )
    assert parse_statute_refs(appropriation) == []
    assert parse_statute_refs(resolution) == []
    assert parse_statute_refs(conveyance) == []
    assert parse_statute_refs(None) == []
    assert parse_statute_refs("") == []


def test_nul_glyphs_do_not_hide_the_title():
    text = _bill(
        "To repeal section 1.010, RSMo, and to enact in lieu thereof one new section relating to x.",
        "Section A. Section 1.010, RSMo, is repealed and one new section enacted in lieu thereof, to be known as\n"
        "2 section 1.010, to read as follows:",
    ).replace("AN ACT", "A\x00N ACT")
    assert [r.action for r in parse_statute_refs(text)] == ["repeal", "enact"]
