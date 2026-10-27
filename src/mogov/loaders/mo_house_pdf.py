"""Missouri House bill documents: the PDFs of bill text versions, summaries, fiscal notes and amendments.

`mo_house` parses the House XML into link tables (`mo_house_xml_{bill,senate_act}_{texts,summaries,fiscal_notes,
amendments}`); this stage-2 loader reads those links, fetches each distinct PDF once, lands it unchanged under
RAW_DIR/mo_house_pdf/<session>/<kind>/<file name> (state row per URL in `mo_house_pdf_files`), and extracts its
text with pdfplumber into `mo_house_pdf_texts` (one row per document: joined text, per-page text as JSON, page
count, and the link row's identifying fields). Extraction is stored as-is: small-caps glyphs can come out as NULs
and are cleaned in dbt.

Witness forms print private citizens' contact details and are never fetched (#244); `fetch_document` is the
reusable fetch-and-land helper, so a new kind is one more entry in `KINDS`.

Requests to documents.house.mo.gov (shared with `mo_house`) start at least REQUEST_INTERVAL apart, across every
shard on the machine. Published versions have versioned file names, so a file landed for a closed session is
never fetched again; the open session's files are re-checked weekly and rewritten only when the bytes change.
Options (environment): MOGOV_HOUSE_PDF_KINDS (comma list, default all) and MOGOV_HOUSE_PDF_SESSIONS (comma list
of session codes, default all).
"""

import hashlib
import json
import os
import time
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from typing import ClassVar

import httpx

from mogov import db, obs, pdftext
from mogov.http import client, host_throttle, write_atomic
from mogov.loaders import loader

log = obs.get_logger(__name__)

MAIN_HOST = "documents.house.mo.gov"
DOCS_DIR = "mo_house_pdf"  # under RAW_DIR: <session>/<kind>/<file name>
REQUEST_INTERVAL = 1.0  # seconds between request starts to the host, across all shards
OPEN_SESSION_RECHECK_S = 7 * 86400
RETRIES = 4
# pdfplumber starts a new word when the gap between glyphs exceeds x_tolerance (default 3). The House's Word
# output sets a space at exactly 3.0pt in 12pt Times (amendments, and some lines of bill text), so the default
# glued "AMENDHouse Committee Substitute" together (#639). 2 splits those and still keeps kerned words whole.
# It is part of the pdftext cache key: changing it re-extracts every document from the PDF already on disk.
X_TOLERANCE = 2

# kind -> link tables as (table, link column, index column, LR number expression, version code expression).
# The Senate-act tables have the same columns as the bill tables.
KINDS: dict[str, list[tuple[str, str, str, str, str]]] = {
    "bill_text": [
        (f"mo_house_xml_{p}_texts", "text_link", "text_index", "lr_number", "version_type_code")
        for p in ("bill", "senate_act")
    ],
    "summary": [
        (f"mo_house_xml_{p}_summaries", "summary_text_link", "summary_index", "lr_number", "version_type_code")
        for p in ("bill", "senate_act")
    ],
    "fiscal_note": [
        (f"mo_house_xml_{p}_fiscal_notes", "fiscal_note_link", "fiscal_note_index", "null", "null")
        for p in ("bill", "senate_act")
    ],
    "amendment": [
        (f"mo_house_xml_{p}_amendments", "amendment_text", "amendment_index", "lr_number", "null")
        for p in ("bill", "senate_act")
    ],
}


@dataclass
class DocFile:
    """State of one document URL: where its bytes landed (if they did) or why they did not."""

    TABLE: ClassVar[str] = "mo_house_pdf_files"
    url: str
    kind: str
    session_code: str
    rel_path: str | None
    size_bytes: int | None
    sha256: str | None
    http_status: int | None
    content_type: str | None
    error: str | None
    landed_at: (
        datetime | None
    )  # the file's last write or (open session) last weekly re-check; a re-run of a closed session keeps it


@dataclass
class DocText:
    """One row per document URL. Identifying fields come from the first link row (by session, file, index) that
    names the URL; `n_links` counts the link rows, since versions can share a summary."""

    TABLE: ClassVar[str] = "mo_house_pdf_texts"
    url: str
    kind: str
    session_code: str
    file_name: str
    lr_number: str | None
    version_code: str | None
    n_links: int
    page_count: int | None
    text: str | None
    pages_json: str | None  # JSON array of per-page text ("" for a page without a text layer)
    error: str | None


@dataclass(frozen=True)
class Link:
    url: str
    kind: str
    session_code: str
    file_name: str
    lr_number: str | None
    version_code: str | None
    n_links: int


@dataclass
class Fetched:
    status: int | None
    content: bytes | None
    content_type: str | None
    error: str | None


def links(kinds: list[str], sessions: set[str] | None = None) -> list[Link]:
    """Every distinct document URL the landed link tables name, with the first link row's fields, in a stable
    order. Missing tables (a session set with no Senate acts) are skipped."""
    parts = []
    for kind in kinds:
        for table, col, idx, lr, ver in KINDS[kind]:
            if db.raw_exists(table):
                parts.append(
                    f"select trim({col}) as url, '{kind}' as kind, session_code, file_name, "
                    f"{lr}::varchar as lr_number, {ver}::varchar as version_code, "
                    f"{idx}::integer as idx "
                    f"from read_parquet('{db.raw_glob(table)}', union_by_name = true) "
                    f"where trim({col}) <> ''"
                )
    if not parts:
        return []
    with db.connect() as con:
        rows = con.execute(
            f"""
            select url, kind, session_code, file_name, lr_number, version_code, count(*) over (partition by url) as n,
                   row_number() over (partition by url order by session_code, file_name, idx, kind) as rn
            from ({" union all ".join(parts)})
            qualify rn = 1
            order by url
            """
        ).fetchall()
    out = [Link(u, k, s, f, lr, v, n) for u, k, s, f, lr, v, n, _ in rows]
    return [x for x in out if sessions is None or x.session_code in sessions]


def rel_path(link: Link) -> str:
    name = link.url.split("?", 1)[0].rsplit("/", 1)[-1] or "index"
    host = httpx.URL(link.url).host
    if host != MAIN_HOST:  # a few old links use another host for a file the main host also serves
        name = f"{host}__{name}"
    return f"{DOCS_DIR}/{link.session_code}/{link.kind}/{name}"


def fetch_document(url: str, *, interval: float = REQUEST_INTERVAL, retries: int = RETRIES) -> Fetched:
    """GET one document, never raising: a non-2xx status or a transport error comes back as data so it can be
    landed as a row. Not cached (the caller lands the bytes); every request waits its turn at the host throttle."""
    if not url.lower().startswith(("http://", "https://")):
        return Fetched(None, None, None, "not an http(s) URL")
    host = httpx.URL(url).host
    last = Fetched(None, None, None, "no attempt")
    for attempt in range(retries):
        try:
            with host_throttle(host, interval):
                started = time.perf_counter()
                resp = client().get(url)
            obs.http_requests.add(1, {"host": host, "cache_hit": False})
            obs.http_duration.record(time.perf_counter() - started, {"host": host, "status": resp.status_code})
            obs.http_bytes.add(len(resp.content), {"host": host})
        except httpx.HTTPError as exc:
            last = Fetched(None, None, None, f"{type(exc).__name__}: {exc}")
        else:
            ctype = resp.headers.get("content-type")
            if resp.status_code == 429 or resp.status_code >= 500:
                last = Fetched(resp.status_code, None, ctype, f"HTTP {resp.status_code}")
            elif resp.status_code >= 400:
                return Fetched(resp.status_code, None, ctype, f"HTTP {resp.status_code}")
            else:
                return Fetched(resp.status_code, resp.content, ctype, None)
        if attempt + 1 < retries:
            time.sleep(min(60, 2**attempt * 5))
    return last


def _is_open(session_code: str) -> bool:
    return 2000 + int(session_code[:2]) >= date.today().year


def land(link: Link, fetcher=None, *, fetch: bool = True) -> tuple[DocFile | None, bytes | None]:
    """Make sure the document's bytes are on disk and describe them. A closed session's file already landed is
    read, not fetched; the open session's is re-checked weekly. Bytes that did not change are not rewritten.
    With fetch=False (the document is outside the selected kinds/sessions) only a file already on disk is used, and
    nothing is returned for one that is not."""
    rel = rel_path(link)
    dest = db.RAW_DIR / rel
    if dest.exists():
        age = time.time() - dest.stat().st_mtime
        if not fetch or not _is_open(link.session_code) or age < OPEN_SESSION_RECHECK_S:
            data = dest.read_bytes()
            return _described(link, rel, dest, data), data
    if not fetch:
        return None, None
    got = (fetcher or fetch_document)(link.url)
    error = got.error
    if got.content is not None and got.content[:5] != b"%PDF-":
        error = "not a PDF"  # the site answers some bad URLs with 200 and an HTML page
    if error is not None or got.content is None:
        if dest.exists():  # a failed re-check must not lose the good file already landed: keep and describe it
            log.warning("mo_house_pdf.recheck_failed", url=link.url, error=error)
            data = dest.read_bytes()
            return _described(link, rel, dest, data), data
        return DocFile(
            link.url, link.kind, link.session_code, None, None, None, got.status, got.content_type, error, None
        ), None
    if dest.exists() and dest.read_bytes() == got.content:
        os.utime(dest)  # checked just now
    else:
        write_atomic(dest, got.content)
    return _described(link, rel, dest, got.content), got.content


def _described(link: Link, rel: str, dest: Path, data: bytes) -> DocFile:
    landed = datetime.fromtimestamp(dest.stat().st_mtime, UTC)
    return DocFile(
        link.url,
        link.kind,
        link.session_code,
        rel,
        len(data),
        hashlib.sha256(data).hexdigest(),
        200,  # a landed file is a PDF the site served with 200 (also what a re-run reports for a kept file)
        "application/pdf",
        None,
        landed,
    )


def extract(link: Link, data: bytes | None, error: str | None) -> DocText:
    """The text row for a document: per-page text via pdfplumber, or the error that stopped it."""
    base = (link.url, link.kind, link.session_code, link.file_name, link.lr_number, link.version_code, link.n_links)
    if data is None:
        return DocText(*base, None, None, None, error or "not fetched")
    try:
        pages = pdftext.page_texts(data, layout=False, x_tolerance=X_TOLERANCE)
    except Exception as exc:  # a corrupt PDF is a row, not a failed run
        return DocText(*base, None, None, None, f"{type(exc).__name__}: {exc}")
    return DocText(*base, len(pages), "\n".join(pages), json.dumps(pages), None)


def _csv_env(name: str) -> list[str]:
    return [v.strip() for v in os.environ.get(name, "").split(",") if v.strip()]


def units(shard: db.Shard) -> list[Link]:
    """This shard's share of all the document URLs: assigned by the URL, so the split holds across runs."""
    return shard.take(links(list(KINDS)), key=lambda x: x.url)


def _iter_rows(mine: list[Link], kinds: set[str], sessions: set[str] | None) -> Iterator[tuple[DocFile, DocText]]:
    progress = obs.Progress("house documents", len(mine), log)
    for link in mine:
        progress.tick()
        wanted = link.kind in kinds and (sessions is None or link.session_code in sessions)
        file_row, data = land(link, fetch=wanted)
        if file_row is not None:
            yield file_row, extract(link, data, file_row.error)
    progress.finish()


@loader("mo_house_pdf", stage=2, service="documents.house.mo.gov", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: distinct document URLs. Each shard lands and reads its own; every shard lists the same URLs from the
    `mo_house` link tables, so the split needs no coordination. The kind/session options only limit what is
    fetched: documents already on disk outside them still get their rows, so pieces of a first run add up."""
    kinds = _csv_env("MOGOV_HOUSE_PDF_KINDS") or list(KINDS)
    if unknown := set(kinds) - set(KINDS):
        raise SystemExit(f"unknown MOGOV_HOUSE_PDF_KINDS {sorted(unknown)}; choose from {sorted(KINDS)}")
    sessions = set(_csv_env("MOGOV_HOUSE_PDF_SESSIONS")) or None
    with db.TableSink(shard, tables=[DocFile, DocText]) as sink:
        for file_row, text_row in _iter_rows(units(shard), set(kinds), sessions):
            if file_row.error:
                log.warning("mo_house_pdf.failed", url=file_row.url, error=file_row.error)
            sink.add(file_row)
            sink.add(text_row)
    return sink.counts
