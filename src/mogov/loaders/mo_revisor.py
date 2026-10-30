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

Each section version lands as the page's content block, verbatim, plus its text split into paragraphs and
fetched_at (when the page came from the site, from the HTTP cache entry's fetch time); dbt parses dates,
status and the history citations. Units: chapters, plus rx.aspx (owned by one shard).
"""

import os
import re
import time
from collections.abc import Callable
from datetime import UTC, datetime
from urllib.parse import urlsplit

import httpx
import lxml.html

from mogov import db, obs
from mogov.http import fetch_stamped, pause_host
from mogov.loaders import loader

log = obs.get_logger(__name__)

HOST = "revisor.mo.gov"
BASE = f"https://{HOST}/main"
# The site's rule: requests from one IP less than a second apart, several times in 30 seconds, get a warning page
# (served with 200 in place of the page asked for); keep going and every request from that IP, browsers included,
# redirects to Block.aspx. ~10 requests/s from three shards got an IP blocked within two minutes on 2026-10-25.
# Requests are paced by a lock shared by every process on the machine (http.host_throttle): each starts at least
# POLITE_DELAY after the last, whichever shard sent it, so shards add no speed. (Per-shard sleeps of delay x shards
# let two shards' requests land less than a second apart: ~400-520 such gaps an hour with 2-4 shards.) Cloud Run
# tasks don't share a filesystem, so the loader refuses to run as more than one task. Even at 1.5 s a single shard
# drew one warning after ~600 pages (other traffic from the same IP counts too), so a warning backs off and
# retries; only repeated warnings or a block stop the load.
POLITE_DELAY = 2.0
WARNING_BACKOFF = (60, 300, 900)
# The warning page is also what a section page that doesn't exist returns. For those, one retry after a minute tells
# the two apart (a real too-fast warning has cleared by then); a page still refused is skipped and logged, and
# several skipped in a row stop the load (the IP is being warned for real).
SECTION_WARNING_BACKOFF = (60,)
MAX_CONSECUTIVE_SKIPS = 3
# Refusals that alternate with good pages never reach the consecutive limit, so the run's total is capped too: more
# than max(MIN_SKIPS_ALLOWED, MAX_SKIPPED_SHARE of the pages) skipped fails the load (nothing lands).
MIN_SKIPS_ALLOWED = 20
MAX_SKIPPED_SHARE = 0.005
REFUSED_MARKER = b"Recent accesses are tracked over a thirty second interval"
# A section page's content block (header, body, footnotes) runs from CONTENT_START to the page footer. The site has
# also served its home page, with 200 and no redirect, in place of a listed section (161.415, 2026-10); a section
# response without the block is refused like the warning page, so it is retried and never cached.
CONTENT_START = '<div style="margin:.1em 0em .4em .5em;">'
CONTENT_END = '<div id="BOTTOM"'
# A new enactment or amendment is a new version with its own bid (a new URL), found through the chapter lists,
# which are re-read weekly. A version's page only changes with annotations, so it is re-read twice a year.
SECTION_MAX_AGE = 180 * 86400
LIST_MAX_AGE = 7 * 86400
TABLES = ["mo_revisor_chapters", "mo_revisor_sections", "mo_revisor_repeals"]
REPEALS_UNIT = "rx.aspx"

CHAPTER_PATH = "/main/OneChapter.aspx"
SECTION_PATH = "/main/PageSelect.aspx"
CHAPTER_ID = re.compile(r"[0-9A-Za-z]+")  # a chapter id; this matches an attribute value, not markup
# Pages are parsed without ever fetching what they reference (external DTDs, entities); that is also lxml's default.
PARSER = lxml.html.HTMLParser(no_network=True)


class Blocked(RuntimeError):
    """revisor.mo.gov refused the request: this IP is blocked (Block.aspx) or was warned for reading too fast. The
    warning page is also what a page that doesn't exist returns; a listed section never should."""


class Warned(Blocked):
    """The too-fast / no-such-page warning (not yet a block)."""


class Misserved(Warned):
    """Another page (the home page) served with 200 in place of the section asked for."""


def _not_blocked(resp: httpx.Response) -> None:
    if resp.url.path.lower().endswith("/block.aspx"):
        raise Blocked(f"revisor.mo.gov blocked this IP address; stop and retry later ({resp.url})")
    if REFUSED_MARKER in resp.content:
        raise Warned(f"revisor.mo.gov answered with its too-fast / no-such-page warning for {resp.url}")


def _section_served(resp: httpx.Response) -> None:
    _not_blocked(resp)
    if CONTENT_START.encode() not in resp.content:
        raise Misserved(f"revisor.mo.gov served a page without a section content block for {resp.url}")


def _get(
    url: str, params: dict | None = None, *, max_age: float = LIST_MAX_AGE, backoff: tuple[float, ...] | None = None
) -> str:
    return _get_stamped(url, params, max_age=max_age, backoff=backoff)[0]


def _get_stamped(
    url: str,
    params: dict | None = None,
    *,
    max_age: float = LIST_MAX_AGE,
    backoff: tuple[float, ...] | None = None,
    check: Callable[[httpx.Response], None] = _not_blocked,
) -> tuple[str, str]:
    """The page text and fetched_at: when its bytes came from revisor.mo.gov, as an ISO-8601 UTC string. A page
    served from the HTTP cache carries the time of the fetch that filled the cache, not the time it was reused."""
    for wait in (*(WARNING_BACKOFF if backoff is None else backoff), None):
        try:
            page, fetched = fetch_stamped(url, params, max_age=max_age, min_interval=POLITE_DELAY, check=check)
            return page.decode("utf-8", "replace"), datetime.fromtimestamp(fetched, UTC).isoformat(timespec="seconds")
        except Warned:
            if wait is None:
                raise
            log.warning("mo_revisor.warned", url=url, params=params, backoff_s=wait)
            # host-wide: other shards (processes sharing the cache) must stop requesting too, not just this one
            pause_host(HOST, wait)
            time.sleep(wait)
    raise AssertionError("unreachable")


def _query(href: str, path: str) -> dict[str, str] | None:
    """The (undecoded) query parameters of a site-relative href on `path`, or None for any other link (an
    absolute or scheme-relative href is another site's, even when its path matches)."""
    split = urlsplit(href.strip())
    if split.scheme or split.netloc or split.path != path:
        return None
    return dict(part.partition("=")[::2] for part in split.query.split("&"))


def chapter_link(href: str) -> str | None:
    """An OneChapter.aspx link -> its chapter id (the only parameter), else None."""
    query = _query(href, CHAPTER_PATH)
    if query is None or list(query) != ["chapter"] or not CHAPTER_ID.fullmatch(query["chapter"]):
        return None
    return query["chapter"]


def section_link(href: str) -> tuple[str, int] | None:
    """A PageSelect.aspx link -> (section, bid), else None."""
    query = _query(href, SECTION_PATH)
    if query is None or not query.get("section") or not re.fullmatch(r"[0-9]+", query.get("bid", "")):
        return None
    return query["section"].strip(), int(query["bid"])


def _text(el) -> str:
    return re.sub(r"\s+", " ", el.text_content()).strip()


def parse_toc(page: str) -> list[dict]:
    """Home.aspx -> [{title, chapter, chapter_name}] in the site's order."""
    rows = []
    for details in lxml.html.fromstring(page, parser=PARSER).iter("details"):
        spans = details.find("summary").findall("span") if details.find("summary") is not None else []
        title = _text(spans[-1]) if spans else None
        for a in details.iterfind(".//a[@href]"):
            chapter = chapter_link(a.get("href"))
            if chapter:
                name = _text(a)
                rows.append({"title": title, "chapter": chapter, "chapter_name": name.partition(" ")[2] or name})
    return rows


def parse_chapter(page: str) -> list[tuple[str, int]]:
    """A chapter page -> its (section, bid) versions, in page order, without duplicates."""
    seen: dict[tuple[str, int], None] = {}
    for a in lxml.html.fromstring(page, parser=PARSER).iterfind(".//a[@href]"):
        if link := section_link(a.get("href")):
            seen[link] = None
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
    start = page.find(CONTENT_START)
    end = page.find(CONTENT_END, start)
    if start < 0 or end < 0:
        raise ValueError("section page without a content block")
    block = page[start:end]
    root = lxml.html.fragment_fromstring(block, create_parent="div", parser=PARSER)
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
    in_transfers = False  # the transferred sections follow the element with id="xfer", in document order
    for el in lxml.html.fromstring(page, parser=PARSER).iter():
        if el.get("id") == "xfer":
            in_transfers = True
        if el.tag != "tr" or el.get("style") != "width:100%;":
            continue
        link = next((x for a in el.iterfind(".//a[@href]") if (x := section_link(a.get("href")))), None)
        if not link:
            continue
        note_cell = list(el.iter("td"))[1]
        date_span = note_cell.find("span")
        date = _text(date_span).strip("() ") if date_span is not None else None
        if date_span is not None:
            date_span.drop_tree()
        rows.append(
            {
                "kind": "transferred" if in_transfers else "repealed",
                "section": link[0],
                "bid": link[1],
                "note": _text(note_cell),
                "date": date,
            }
        )
    return rows


@loader("mo_revisor", service="revisor.mo.gov", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: chapters (their section pages), plus the repeals page."""
    tasks = int(os.environ.get("CLOUD_RUN_TASK_COUNT") or 1)
    if tasks > 1:
        raise RuntimeError(
            f"mo_revisor can't run as {tasks} Cloud Run tasks: tasks don't share a filesystem, so their requests to "
            "revisor.mo.gov can't be paced together and the site blocks the IP. Run it as one task "
            "(--tasks 1; use --shards for processes inside that task)."
        )
    toc_url = f"{BASE}/Home.aspx"
    toc = parse_toc(_get(toc_url))
    if not toc:
        raise RuntimeError("revisor table of contents lists no chapters; the page layout may have changed")
    chapters = shard.take(toc, key=lambda c: c["chapter"])
    with db.JsonSink(shard, source_url=toc_url, tables=TABLES) as sink:
        for c in chapters:
            sink.add("mo_revisor_chapters", c["chapter"], c)
        if shard.owns(REPEALS_UNIT):
            rx_url = f"{BASE}/rx.aspx"
            rx_page, rx_fetched_at = _get_stamped(rx_url)
            for r in parse_repeals(rx_page):
                sink.add(
                    "mo_revisor_repeals",
                    f"{r['section']}/{r['bid']}",
                    {**r, "fetched_at": rx_fetched_at},
                    source_url=rx_url,
                )
        versions = []
        for c in chapters:
            listed = parse_chapter(_get(f"{BASE}/OneChapter.aspx", {"chapter": c["chapter"]}))
            if not listed:  # every section of the chapter repealed or transferred
                log.info("mo_revisor.empty_chapter", chapter=c["chapter"])
            versions += [(c["chapter"], section, bid) for section, bid in listed]
        progress = obs.Progress("section versions", len(versions), log)
        url = f"{BASE}/OneSection.aspx"
        skipped = 0
        skipped_total = 0
        for chapter, section, bid in versions:
            try:
                page, fetched_at = _get_stamped(
                    url,
                    {"section": section, "bid": bid},
                    max_age=SECTION_MAX_AGE,
                    backoff=SECTION_WARNING_BACKOFF,
                    check=_section_served,
                )
            except Warned:
                skipped += 1
                skipped_total += 1
                log.warning(
                    "mo_revisor.section_page_refused",
                    section=section,
                    bid=bid,
                    consecutive=skipped,
                    total=skipped_total,
                )
                if skipped >= MAX_CONSECUTIVE_SKIPS:
                    raise
                progress.tick()
                continue
            skipped = 0
            try:
                parsed = parse_section(page)
            except ValueError as e:
                raise ValueError(f"section {section} (bid {bid}): {e}") from e
            sink.add(
                "mo_revisor_sections",
                f"{section}/{bid}",
                {"chapter": chapter, "section": section, "bid": bid, **parsed, "fetched_at": fetched_at},
                source_url=f"{url}?section={section}&bid={bid}",
            )
            progress.tick()
        progress.finish()
        log.info("mo_revisor.sections_skipped", total=skipped_total, of=len(versions))
        limit = max(MIN_SKIPS_ALLOWED, MAX_SKIPPED_SHARE * len(versions))
        if skipped_total > limit:
            raise RuntimeError(
                f"mo_revisor skipped {skipped_total} of {len(versions)} section pages as refused (limit {limit:.0f}); "
                "the site is warning this IP, not reporting missing pages"
            )
    return sink.counts
