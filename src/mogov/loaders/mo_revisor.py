"""Missouri Revisor of Statutes (revisor.mo.gov): the Revised Statutes of Missouri (RSMo), section by section.

The site has no bulk download; every page is server-rendered HTML.
- Home.aspx is the table of contents: titles (roman numerals) and their chapters.
- OneChapter.aspx?chapter=N lists the chapter's sections in force, one link per section *version* (`bid`).
  A section enacted more than once, or amended with a later effective date, has several versions listed
  side by side (27.117 has one version effective 28 Aug 2026 and one effective 1 Jul 2027).
- OneSection.aspx?section=S&bid=B is one version: heading, text, effective-date line and footnotes (the
  session-law history such as "(RSMo 1939 § 645, A.L. 1957 p. 587, A.L. 2015 S.B. 239)" and case notes).
- rx.aspx is one ~10 MB page listing every repealed and transferred section with its repealing act and date,
  so those ~15,000 sections need no page of their own.

Each section version lands as the page's content block, verbatim, plus its text split into paragraphs; dbt
parses dates, status and the history citations. Units: chapters, plus rx.aspx (owned by one shard).
"""

import re

import lxml.html

from mogov import db, obs
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://revisor.mo.gov/main"
POLITE_DELAY = 0.3
# Statutes change mostly on 28 August (plus emergency clauses and contingent effective dates); a month-old
# copy of a section is fine. The chapter lists are re-read weekly so new versions are found sooner.
SECTION_MAX_AGE = 30 * 86400
LIST_MAX_AGE = 7 * 86400
TABLES = ["mo_revisor_chapters", "mo_revisor_sections", "mo_revisor_repeals"]
REPEALS_UNIT = "rx.aspx"

CHAPTER_LINK = re.compile(r'href="/main/OneChapter\.aspx\?chapter=([0-9A-Za-z]+)"')
SECTION_LINK = re.compile(r'href="/main/PageSelect\.aspx\?section=([^&"]+)&amp;bid=(\d+)')


def _text(el) -> str:
    return re.sub(r"\s+", " ", el.text_content()).strip()


def parse_toc(page: str) -> list[dict]:
    """Home.aspx -> [{title, chapter, chapter_name}] in the site's order."""
    rows = []
    for details in lxml.html.fromstring(page).iter("details"):
        spans = details.find("summary").findall("span") if details.find("summary") is not None else []
        title = _text(spans[-1]) if spans else None
        for a in details.iterfind(".//a[@href]"):
            m = CHAPTER_LINK.search(f'href="{a.get("href")}"')
            if m:
                name = _text(a)
                rows.append({"title": title, "chapter": m.group(1), "chapter_name": name.partition(" ")[2] or name})
    return rows


def parse_chapter(page: str) -> list[tuple[str, int]]:
    """A chapter page -> its (section, bid) versions, in page order, without duplicates."""
    seen: dict[tuple[str, int], None] = {}
    for section, bid in SECTION_LINK.findall(page):
        seen[(section.strip(), int(bid))] = None
    return list(seen)


def _blocks(el) -> list[str]:
    """The text blocks of one body element: a paragraph's text, a table's rows (cells tab-separated, one row
    per line), or the blocks of a wrapper div (tables and forms come wrapped in divs)."""
    if el.tag == "table":
        return ["\n".join("\t".join(_text(c) for c in tr.xpath("./td|./th")) for tr in el.iter("tr"))]
    if el.tag == "div" and len(el):
        return [t for child in el for t in _blocks(child)]
    text = _text(el).strip("\xad ")  # soft hyphens pad the spacer paragraphs around tables
    return [text] if text else []


def parse_section(page: str) -> dict:
    """A section page -> {html, title_line, effective, historical, heading, paragraphs, footnotes}.

    html is the content block as served (header with title and effective line, body, footnotes); the
    other fields are its text, unparsed."""
    start = page.find('<div style="margin:.1em 0em .4em .5em;">')
    end = page.find('<div id="BOTTOM"', start)
    if start < 0 or end < 0:
        raise ValueError("section page without a content block")
    block = page[start:end]
    root = lxml.html.fragment_fromstring(block, create_parent="div")
    header = root[0]
    title_p = header.find("p")
    effdt = root.find('.//span[@id="effdt"]')
    body = root.find('.//div[@class="norm"]')
    heading = body.find('.//span[@class="bold"]') if body is not None else None
    paragraphs, footnotes = [], []
    if body is not None:
        for el in body:
            if el.tag == "div" and el.get("class") == "foot":
                footnotes = [t for p in el.iterfind(".//p[@class='norm']") if (t := _text(p))]
            else:
                paragraphs += _blocks(el)
    return {
        "html": block,
        "title_line": _text(title_p) if title_p is not None else None,
        "effective": _text(effdt) if effdt is not None else None,
        "historical": effdt is not None and effdt.find('.//span[@title="this section is historical"]') is not None,
        "heading": _text(heading) if heading is not None else None,
        "paragraphs": paragraphs,
        "footnotes": footnotes,
    }


def parse_repeals(page: str) -> list[dict]:
    """rx.aspx -> [{kind: repealed|transferred, section, bid, note, date}], note and date as printed."""
    rows = []
    xfer = page.find('id="xfer"')
    for m in re.finditer(r'<tr style="width:100%;">(.*?)</tr>', page, re.S):
        link = SECTION_LINK.search(m.group(1))
        if not link:
            continue
        cells = lxml.html.fragment_fromstring(m.group(0), create_parent="table").iter("td")
        cells = list(cells)
        note_cell = cells[1]
        date_span = note_cell.find("span")
        date = _text(date_span).strip("() ") if date_span is not None else None
        if date_span is not None:
            date_span.drop_tree()
        rows.append(
            {
                "kind": "transferred" if 0 <= xfer < m.start() else "repealed",
                "section": link.group(1).strip(),
                "bid": int(link.group(2)),
                "note": _text(note_cell),
                "date": date,
            }
        )
    return rows


@loader("mo_revisor", service="revisor.mo.gov", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: chapters (their section pages), plus the repeals page."""
    toc_url = f"{BASE}/Home.aspx"
    toc = parse_toc(fetch(toc_url, max_age=LIST_MAX_AGE, delay=POLITE_DELAY).decode("utf-8", "replace"))
    if not toc:
        raise RuntimeError("revisor table of contents lists no chapters; the page layout may have changed")
    chapters = shard.take(toc, key=lambda c: c["chapter"])
    with db.JsonSink(shard, source_url=toc_url, tables=TABLES) as sink:
        for c in chapters:
            sink.add("mo_revisor_chapters", c["chapter"], c)
        if shard.owns(REPEALS_UNIT):
            rx_url = f"{BASE}/rx.aspx"
            page = fetch(rx_url, max_age=LIST_MAX_AGE, delay=POLITE_DELAY).decode("utf-8", "replace")
            for r in parse_repeals(page):
                sink.add("mo_revisor_repeals", f"{r['section']}/{r['bid']}", r, source_url=rx_url)
        versions = []
        for c in chapters:
            url = f"{BASE}/OneChapter.aspx"
            page = fetch(url, {"chapter": c["chapter"]}, max_age=LIST_MAX_AGE, delay=POLITE_DELAY)
            listed = parse_chapter(page.decode("utf-8", "replace"))
            if not listed:
                log.warning("mo_revisor.empty_chapter", chapter=c["chapter"])
            versions += [(c["chapter"], section, bid) for section, bid in listed]
        progress = obs.Progress("section versions", len(versions), log)
        for chapter, section, bid in versions:
            url = f"{BASE}/OneSection.aspx"
            params = {"section": section, "bid": bid}
            page = fetch(url, params, max_age=SECTION_MAX_AGE, delay=POLITE_DELAY).decode("utf-8", "replace")
            try:
                parsed = parse_section(page)
            except ValueError:
                log.warning("mo_revisor.unparsed_section", section=section, bid=bid)
                continue
            sink.add(
                "mo_revisor_sections",
                f"{section}/{bid}",
                {"chapter": chapter, "section": section, "bid": bid, **parsed},
                source_url=f"{url}?section={section}&bid={bid}",
            )
            progress.tick()
        progress.finish()
    return sink.counts
