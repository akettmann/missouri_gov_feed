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

import httpx
import lxml.html

from mogov import db, obs
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://revisor.mo.gov/main"
# The site's rule: requests from one IP less than a second apart, several times in 30 seconds, get a warning page
# (served with 200 in place of the page asked for); keep going and every request from that IP, browsers included,
# redirects to Block.aspx. ~10 requests/s from three shards got an IP blocked within two minutes on 2026-10-25.
# Each shard waits POLITE_DELAY x the shard count between requests, so all shards together from one IP stay under
# one request per POLITE_DELAY.
POLITE_DELAY = 1.5
REFUSED_MARKER = b"Recent accesses are tracked over a thirty second interval"
# A new enactment or amendment is a new version with its own bid (a new URL), found through the chapter lists,
# which are re-read weekly. A version's page only changes with annotations, so it is re-read twice a year.
SECTION_MAX_AGE = 180 * 86400
LIST_MAX_AGE = 7 * 86400
TABLES = ["mo_revisor_chapters", "mo_revisor_sections", "mo_revisor_repeals"]
REPEALS_UNIT = "rx.aspx"

CHAPTER_LINK = re.compile(r'href="/main/OneChapter\.aspx\?chapter=([0-9A-Za-z]+)"')
SECTION_LINK = re.compile(r'href="/main/PageSelect\.aspx\?section=([^&"]+)&amp;bid=(\d+)')


class Blocked(RuntimeError):
    """revisor.mo.gov refused the request: this IP is blocked (Block.aspx) or was warned for reading too fast. The
    warning page is also what a page that doesn't exist returns; a listed section never should."""


def _not_blocked(resp: httpx.Response) -> None:
    if resp.url.path.lower().endswith("/block.aspx"):
        raise Blocked(f"revisor.mo.gov blocked this IP address; stop and retry later ({resp.url})")
    if REFUSED_MARKER in resp.content:
        raise Blocked(f"revisor.mo.gov answered with its too-fast / no-such-page warning for {resp.url}")


def _get(url: str, params: dict | None = None, *, max_age: float = LIST_MAX_AGE, shards: int = 1) -> str:
    page = fetch(url, params, max_age=max_age, delay=POLITE_DELAY * shards, check=_not_blocked)
    return page.decode("utf-8", "replace")


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
    """A section page -> {html, title_line, effective, historical, heading, text, footnotes}.

    html is the content block as served (header with title and effective line, body, footnotes); the
    other fields are its text, unparsed. text is the body's paragraphs separated by blank lines (table rows
    one per line, cells tab-separated)."""
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
        "text": "\n\n".join(paragraphs),
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
    toc = parse_toc(_get(toc_url, shards=shard.count))
    if not toc:
        raise RuntimeError("revisor table of contents lists no chapters; the page layout may have changed")
    chapters = shard.take(toc, key=lambda c: c["chapter"])
    with db.JsonSink(shard, source_url=toc_url, tables=TABLES) as sink:
        for c in chapters:
            sink.add("mo_revisor_chapters", c["chapter"], c)
        if shard.owns(REPEALS_UNIT):
            rx_url = f"{BASE}/rx.aspx"
            for r in parse_repeals(_get(rx_url, shards=shard.count)):
                sink.add("mo_revisor_repeals", f"{r['section']}/{r['bid']}", r, source_url=rx_url)
        versions = []
        for c in chapters:
            listed = parse_chapter(_get(f"{BASE}/OneChapter.aspx", {"chapter": c["chapter"]}, shards=shard.count))
            if not listed:  # every section of the chapter repealed or transferred
                log.info("mo_revisor.empty_chapter", chapter=c["chapter"])
            versions += [(c["chapter"], section, bid) for section, bid in listed]
        progress = obs.Progress("section versions", len(versions), log)
        url = f"{BASE}/OneSection.aspx"
        for chapter, section, bid in versions:
            page = _get(url, {"section": section, "bid": bid}, max_age=SECTION_MAX_AGE, shards=shard.count)
            try:
                parsed = parse_section(page)
            except ValueError as e:
                raise ValueError(f"section {section} (bid {bid}): {e}") from e
            sink.add(
                "mo_revisor_sections",
                f"{section}/{bid}",
                {"chapter": chapter, "section": section, "bid": bid, **parsed},
                source_url=f"{url}?section={section}&bid={bid}",
            )
            progress.tick()
        progress.finish()
    return sink.counts
