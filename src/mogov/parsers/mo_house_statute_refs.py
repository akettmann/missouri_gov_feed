"""RSMo section references in a House bill text: the sections the bill repeals, amends or enacts (#594).

A bill's enacting title is the paragraph between `AN ACT` and `Be it enacted ...`:

    AN ACT To repeal sections 1.010, 2.020 to 2.040 and 3.030, RSMo, and to enact in lieu thereof four new
    sections relating to ...

and `Section A.` names the new sections: `... enacted in lieu thereof, to be known as sections 1.010, 1.011 ... to
read as follows`. The title gives `repeal` rows (`To amend section ..., RSMo, by ...` gives `amend`), the Section A
clause gives `enact` rows. `To amend chapter 160, RSMo, by adding thereto one new section` has no section to
repeal, only an enacted one. Appropriation bills, land conveyances and joint resolutions that amend the
Constitution name no RSMo section and give no rows.

Sections are kept as written: a range ("2.020 to 2.040") is one row with both endpoints and is expanded against the
statutes in dbt. The text is the pdfplumber extraction, in which Section A's lines carry a leading line number
("2 sections enacted in lieu"), removed before reading. Nothing is looked up or validated here.
"""

import re
from dataclasses import dataclass

# chapter.section: "1.010", "135.1150", "30A.010", with the uniform codes' "400.3-505" and "456.4-411A"
_ID = r"\d{1,3}[A-Z]?\.\d{1,5}[A-Z]?(?:-\d{1,4}[A-Z]?)?"
_REF = re.compile(rf"(?<![\w.-])(?P<start>{_ID})(?![\w-])(?:\s+(?:to|through)\s+(?P<end>{_ID})(?![\w-]))?")
_RSMO = re.compile(r"RSMo(?:\s+Supp\.\s*(\d{4}))?")
_TITLE = re.compile(r"\bAN ACT\b(?P<title>.*?)Be it enacted", re.S)
_REPEAL = re.compile(
    r"\bTo (?P<verb>repeal|amend) (?P<body>sections?\b.*?)(?=\bto enact\b|\bby adding\b|\brelating to\b|$)", re.S
)
# searched in text with the line numbers removed
_SECTION_A = re.compile(r"Be it enacted.*?\bSection A\.(?P<body>.*?)\bto read as follows", re.S)
_KNOWN_AS = re.compile(r"\bto be known as\s+sections?\b(?P<ids>.*)$", re.S)
_LINE_NUMBER = re.compile(r"(?m)^\d{1,3}(?: |$)")


SECTION_A_WINDOW = 80_000  # characters after the enacting clause searched for Section A (long omnibus lists)


@dataclass(frozen=True)
class StatuteRef:
    ordinal: int  # 1-based within the action, in the order written
    action: str  # repeal, amend or enact
    section_start: str  # the section, or the first section of a range, as written
    section_end: str | None  # the last section of a range ("2.020 to 2.040"), else None
    supp_year: int | None  # "RSMo Supp. 2023" after the reference: the section is from that year's supplement
    clause: str  # the title or Section A text the reference came from, whitespace collapsed


def _refs(action: str, text: str, clause: str) -> list[StatuteRef]:
    out = []
    for m in _REF.finditer(text):
        supp = _RSMO.search(text, m.end())
        year = int(supp.group(1)) if supp and supp.group(1) else None
        out.append(StatuteRef(len(out) + 1, action, m.group("start"), m.group("end"), year, clause))
    return out


def _squash(text: str) -> str:
    return " ".join(text.split())


def parse_statute_refs(text: str | None) -> list[StatuteRef]:
    """The repeal/amend references from the enacting title, then the enact references from Section A."""
    if not text:
        return []
    text = text.replace("\x00", "")
    out: list[StatuteRef] = []
    if title := _TITLE.search(text):
        title_text = _squash(title.group("title"))
        if m := _REPEAL.search(title_text):
            out += _refs(m.group("verb"), m.group("body"), _squash(m.group(0)))
    start = text.find("Be it enacted")
    enacting = text[start : start + SECTION_A_WINDOW] if start >= 0 else ""
    if sec := _SECTION_A.search(_squash(_LINE_NUMBER.sub("", enacting))):
        section_a = sec.group("body")
        if m := _KNOWN_AS.search(section_a):
            out += _refs("enact", m.group("ids"), _squash(m.group(0)))
    return out
