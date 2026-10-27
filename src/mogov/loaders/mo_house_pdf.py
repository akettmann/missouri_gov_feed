"""Missouri House bill documents: the PDFs of bill text versions, summaries, fiscal notes and amendments.

`mo_house` parses the House XML into link tables (`mo_house_xml_{bill,senate_act}_{texts,summaries,fiscal_notes,
amendments}`); this stage-2 loader reads those links, fetches each distinct PDF once, lands it unchanged under
RAW_DIR/mo_house_pdf/<session>/<kind>/<file name> (state row per URL in `mo_house_pdf_files`), and extracts its
text with pdfplumber into `mo_house_pdf_texts` (one row per document: joined text, per-page text as JSON, page
count, and the link row's identifying fields). Extraction is stored as-is: small-caps glyphs can come out as NULs
and are cleaned in dbt.

A bill text version's enacting title and Section A are also read for the RSMo sections it repeals or enacts
(`mo_house_pdf_statute_refs`, one row per section or range as written; see `mogov.parsers.mo_house_statute_refs`).

Witness forms print private citizens' contact details and are never fetched (#244); `fetch_document` is the
reusable fetch-and-land helper, so a new kind is one more entry in `KINDS`.

Requests to documents.house.mo.gov (shared with `mo_house`) start at least REQUEST_INTERVAL apart, across every
shard on the machine. Published versions have versioned file names, so a file landed for a closed session is
never fetched again; the open session's files are re-checked weekly (a conditional GET: an unchanged file answers
304) and rewritten only when the bytes change. A closed session's permanent failures (HTTP 4xx, an HTML page where a
PDF should be) are not retried for NEGATIVE_CACHE_S, judged by the previous `mo_house_pdf_files` row; a file whose
size and mtime match that row is not read again (its hash and cached text come from the row). Rows for URLs outside
a filtered run's kinds/sessions are carried over from the previous run.
Options (environment): MOGOV_HOUSE_PDF_KINDS (comma list, default all) and MOGOV_HOUSE_PDF_SESSIONS (comma list
of session codes, default all).
"""

import contextlib
import hashlib
import json
import os
import time
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from typing import ClassVar

import duckdb
import httpx

from mogov import db, obs, pdftext
from mogov.http import client, host_throttle, write_atomic
from mogov.loaders import loader
from mogov.parsers.mo_house_statute_refs import parse_statute_refs

log = obs.get_logger(__name__)

MAIN_HOST = "documents.house.mo.gov"
DOCS_DIR = "mo_house_pdf"  # under RAW_DIR: <session>/<kind>/<file name>
REQUEST_INTERVAL = 1.0  # seconds between request starts to the host, across all shards
OPEN_SESSION_RECHECK_S = 7 * 86400
NEGATIVE_CACHE_S = 30 * 86400  # a closed session's 4xx / not-a-PDF link is not asked for again this long
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
    checked_at: datetime | None = None  # when the site was last asked for this URL (negative-cache clock)
    etag: str | None = None  # validators the site sent with the file, for the weekly conditional re-check
    last_modified: str | None = None


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


@dataclass
class DocStatuteRef:
    """One RSMo section (or range) a bill text version repeals, amends or enacts, from its enacting title and
    Section A (#594; parser in `mogov.parsers.mo_house_statute_refs`). Only `bill_text` documents. Ranges stay as
    written (`section_end` set); dbt expands them."""

    TABLE: ClassVar[str] = "mo_house_pdf_statute_refs"
    url: str
    session_code: str
    file_name: str
    lr_number: str | None
    version_code: str | None
    ordinal: int  # 1-based within the action
    action: str  # repeal, amend or enact
    section_start: str
    section_end: str | None
    supp_year: int | None
    clause: str


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
    etag: str | None = None
    last_modified: str | None = None


def previous_files(attempts: int = 3) -> dict[str, DocFile]:
    """The state rows the last run landed, by URL (empty on a first run). Columns added since an older landing
    read as NULL. A part another shard replaces or drops (a new shard count) between the glob and the read makes
    the read fail with an IO error; the listing is then redone."""
    for attempt in range(attempts):
        try:
            return _read_previous_files()
        except duckdb.IOException:
            if attempt + 1 == attempts:
                raise
            time.sleep(1)
    return {}


def _read_previous_files() -> dict[str, DocFile]:
    if not db.raw_exists(DocFile.TABLE):
        return {}
    names = list(db.row_columns(DocFile))
    with db.connect() as con:
        have = {
            r[0]
            for r in con.execute(
                f"describe select * from read_parquet('{db.raw_glob(DocFile.TABLE)}', union_by_name = true)"
            ).fetchall()
        }
        cols = ", ".join(n if n in have else f"null as {n}" for n in names)
        # the newest row for a URL sorts last; the part file name makes ties (error rows have no landed_at) stable
        rows = con.execute(
            f"select {cols} from read_parquet('{db.raw_glob(DocFile.TABLE)}', union_by_name = true, filename = true) "
            "order by url, coalesce(checked_at, landed_at) nulls first, filename"
        ).fetchall()
    return {r[0]: DocFile(*r) for r in rows}


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


def fetch_document(
    url: str, *, interval: float = REQUEST_INTERVAL, retries: int = RETRIES, headers: dict[str, str] | None = None
) -> Fetched:
    """GET one document, never raising: a non-2xx status or a transport error comes back as data so it can be
    landed as a row. Not cached (the caller lands the bytes); every request waits its turn at the host throttle.
    `headers` (If-None-Match / If-Modified-Since) make it a conditional GET; 304 comes back with no content."""
    if not url.lower().startswith(("http://", "https://")):
        return Fetched(None, None, None, "not an http(s) URL")
    host = httpx.URL(url).host
    last = Fetched(None, None, None, "no attempt")
    for attempt in range(retries):
        try:
            with host_throttle(host, interval):
                started = time.perf_counter()
                resp = client().get(url, headers=headers) if headers else client().get(url)
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
                return Fetched(
                    resp.status_code,
                    None if resp.status_code == 304 else resp.content,
                    ctype,
                    None,
                    resp.headers.get("etag"),
                    resp.headers.get("last-modified"),
                )
        if attempt + 1 < retries:
            time.sleep(min(60, 2**attempt * 5))
    return last


def _is_open(session_code: str) -> bool:
    return 2000 + int(session_code[:2]) >= date.today().year


def _now() -> datetime:
    return datetime.now(UTC)


def _is_permanent(prev: DocFile) -> bool:
    """A failure a retry will not fix: the site said 4xx (other than timeout/rate limit), or answered 200 with
    an HTML page. Timeouts, 429 and 5xx are transient and always retried."""
    if prev.error == "not a PDF":
        return True
    return prev.http_status is not None and 400 <= prev.http_status < 500 and prev.http_status not in (408, 429)


def _unchanged_on_disk(prev: DocFile | None, dest: Path) -> bool:
    """The file is the one the previous row describes (same size, same mtime), so its hash need not be recomputed."""
    if prev is None or prev.error is not None or prev.sha256 is None or prev.landed_at is None:
        return False
    st = dest.stat()
    return st.st_size == prev.size_bytes and abs(st.st_mtime - prev.landed_at.timestamp()) < 0.001


def _kept(link: Link, rel: str, dest: Path, prev: DocFile) -> DocFile:
    """The previous row for a file left as it was (re-stamped with the file's mtime, which a touch moves)."""
    landed = datetime.fromtimestamp(dest.stat().st_mtime, UTC)
    return DocFile(
        link.url,
        link.kind,
        link.session_code,
        rel,
        prev.size_bytes,
        prev.sha256,
        200,
        "application/pdf",
        None,
        landed,
        prev.checked_at,
        prev.etag,
        prev.last_modified,
    )


def land(
    link: Link, fetcher=None, *, fetch: bool = True, prev: DocFile | None = None
) -> tuple[DocFile | None, bytes | None]:
    """Make sure the document's bytes are on disk and describe them. A closed session's file already landed is
    not fetched; the open session's is re-checked weekly with a conditional GET. Bytes that did not change are not
    rewritten. With fetch=False (the document is outside the selected kinds/sessions) only a file already on disk
    is used, and a failure recorded by an earlier run is carried over. `prev` is the last run's row for the URL:
    it lets a file whose size and mtime still match be described without reading it (the bytes come back as
    None; the caller reads them only if it needs them), and drives the negative cache and the validators.
    Returns (None, None) when there is nothing to describe."""
    rel = rel_path(link)
    dest = db.RAW_DIR / rel
    if dest.exists():
        age = time.time() - dest.stat().st_mtime
        if not fetch or not _is_open(link.session_code) or age < OPEN_SESSION_RECHECK_S:
            if _unchanged_on_disk(prev, dest):
                return _kept(link, rel, dest, prev), None
            data = dest.read_bytes()
            return _described(link, rel, dest, data, prev), data
    elif prev is not None and prev.error is not None:
        # a failure from an earlier run, and no file to protect
        if not fetch:
            return prev, None  # error history survives a run that is limited to other kinds/sessions
        if (
            not _is_open(link.session_code)
            and _is_permanent(prev)
            and prev.checked_at is not None
            and (_now() - prev.checked_at).total_seconds() < NEGATIVE_CACHE_S
        ):
            return prev, None
    if not fetch:
        return None, None
    headers = None
    if dest.exists() and prev is not None and prev.error is None and prev.size_bytes == dest.stat().st_size:
        headers = {}
        if prev.etag:
            headers["If-None-Match"] = prev.etag
        if prev.last_modified:
            headers["If-Modified-Since"] = prev.last_modified
    got = (fetcher or fetch_document)(link.url, **({"headers": headers} if headers else {}))
    if got.status == 304 and got.error is None and dest.exists() and headers and prev is not None:
        os.utime(dest)  # the site says the file did not change: checked just now
        kept = _kept(link, rel, dest, prev)
        kept.checked_at = _now()
        return kept, None
    error = got.error
    if got.content is not None and got.content[:5] != b"%PDF-":
        error = "not a PDF"  # the site answers some bad URLs with 200 and an HTML page
    if error is not None or got.content is None:
        if dest.exists():  # a failed re-check must not lose the good file already landed: keep and describe it
            log.warning("mo_house_pdf.recheck_failed", url=link.url, error=error)
            data = dest.read_bytes()
            return _described(link, rel, dest, data, prev), data
        return DocFile(
            link.url, link.kind, link.session_code, None, None, None, got.status, got.content_type, error, None, _now()
        ), None
    if dest.exists() and dest.read_bytes() == got.content:
        os.utime(dest)  # checked just now
    else:
        write_atomic(dest, got.content)
    row = _described(link, rel, dest, got.content, None)
    row.checked_at, row.etag, row.last_modified = _now(), got.etag, got.last_modified
    return row, got.content


def _described(link: Link, rel: str, dest: Path, data: bytes, prev: DocFile | None = None) -> DocFile:
    """Describe a file from its bytes. The validators of `prev` are kept only when `prev` describes these bytes."""
    landed = datetime.fromtimestamp(dest.stat().st_mtime, UTC)
    sha = hashlib.sha256(data).hexdigest()
    same = prev is not None and prev.error is None and prev.sha256 == sha
    return DocFile(
        link.url,
        link.kind,
        link.session_code,
        rel,
        len(data),
        sha,
        200,  # a landed file is a PDF the site served with 200 (also what a re-run reports for a kept file)
        "application/pdf",
        None,
        landed,
        prev.checked_at if same else None,
        prev.etag if same else None,
        prev.last_modified if same else None,
    )


def _text_row(link: Link, pages: list[str]) -> DocText:
    base = (link.url, link.kind, link.session_code, link.file_name, link.lr_number, link.version_code, link.n_links)
    return DocText(*base, len(pages), "\n".join(pages), json.dumps(pages), None)


CACHED = "(cached) "  # prefix on an error row reported from a timeout marker


def _timeout_marker(sha256_hex: str) -> Path:
    return pdftext.CACHE_DIR / "mo_house_pdf_timeouts" / f"{sha256_hex}-x{X_TOLERANCE}-{pdftext._EXTRACTOR}.json"


def _cached_timeout(sha256_hex: str | None) -> str | None:
    """The ExtractTimeout error recorded for this PDF within NEGATIVE_CACHE_S, else None. Without it a document
    that runs out its budget would spend up to pdftext.MAX_SECONDS again on every run (#708)."""
    if sha256_hex is None:
        return None
    try:
        saved = json.loads(_timeout_marker(sha256_hex).read_text())
        if time.time() - saved["at"] < NEGATIVE_CACHE_S:
            return saved["error"]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def _remember_timeout(sha256_hex: str, error: str) -> None:
    write_atomic(_timeout_marker(sha256_hex), json.dumps({"at": time.time(), "error": error}).encode())


def extract(link: Link, data: bytes | None, error: str | None) -> DocText:
    """The text row for a document: per-page text via pdfplumber, or the error that stopped it. A timeout is
    remembered by the PDF's hash, so later runs report it without extracting again until NEGATIVE_CACHE_S passes."""
    base = (link.url, link.kind, link.session_code, link.file_name, link.lr_number, link.version_code, link.n_links)
    if data is None:
        return DocText(*base, None, None, None, error or "not fetched")
    sha = hashlib.sha256(data).hexdigest()
    if (cached := _cached_timeout(sha)) is not None:
        return DocText(*base, None, None, None, CACHED + cached)
    try:
        pages = pdftext.page_texts(data, layout=False, x_tolerance=X_TOLERANCE)
    except pdftext.ExtractTimeout as exc:
        message = f"{type(exc).__name__}: {exc}"
        log.warning("mo_house_pdf.extract_timeout", url=link.url, error=message)
        # best effort: a marker that cannot be written only costs the next run another try
        with contextlib.suppress(OSError):
            _remember_timeout(sha, message)
        return DocText(*base, None, None, None, message)
    except Exception as exc:  # a corrupt or runaway PDF is a row, not a failed run
        return DocText(*base, None, None, None, f"{type(exc).__name__}: {exc}")
    return _text_row(link, pages)


def extract_landed(link: Link, row: DocFile) -> DocText:
    """The text row for a file described without reading it: the cached text for its recorded hash, else the
    file is read and extracted."""
    pages = pdftext.cached_page_texts(row.sha256, layout=False, x_tolerance=X_TOLERANCE)
    if pages is not None:
        return _text_row(link, pages)
    if (cached := _cached_timeout(row.sha256)) is not None:  # known to time out: do not even read the file
        return DocText(
            link.url, link.kind, link.session_code, link.file_name, link.lr_number, link.version_code, link.n_links,
            None, None, None, CACHED + cached,
        )  # fmt: skip
    return extract(link, (db.RAW_DIR / row.rel_path).read_bytes(), None)


def statute_refs(text_row: DocText) -> list[DocStatuteRef]:
    """The statute references of a bill text version: none for other kinds or a document without text."""
    if text_row.kind != "bill_text" or not text_row.text:
        return []
    return [
        DocStatuteRef(
            text_row.url,
            text_row.session_code,
            text_row.file_name,
            text_row.lr_number,
            text_row.version_code,
            r.ordinal,
            r.action,
            r.section_start,
            r.section_end,
            r.supp_year,
            r.clause,
        )
        for r in parse_statute_refs(text_row.text)
    ]


def _csv_env(name: str) -> list[str]:
    return [v.strip() for v in os.environ.get(name, "").split(",") if v.strip()]


def units(shard: db.Shard) -> list[Link]:
    """This shard's share of all the document URLs: assigned by the URL, so the split holds across runs."""
    return shard.take(links(list(KINDS)), key=lambda x: x.url)


def _iter_rows(
    mine: list[Link], kinds: set[str], sessions: set[str] | None, previous: dict[str, DocFile] | None = None
) -> Iterator[tuple[DocFile, DocText]]:
    previous = previous or {}
    progress = obs.Progress("house documents", len(mine), log)
    for link in mine:
        progress.tick()
        wanted = link.kind in kinds and (sessions is None or link.session_code in sessions)
        file_row, data = land(link, fetch=wanted, prev=previous.get(link.url))
        if file_row is None:
            continue
        if data is None and file_row.error is None:
            yield file_row, extract_landed(link, file_row)
        else:
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
    previous = previous_files()
    with db.TableSink(shard, tables=[DocFile, DocText, DocStatuteRef]) as sink:
        for file_row, text_row in _iter_rows(units(shard), set(kinds), sessions, previous):
            if file_row.error and file_row is not previous.get(file_row.url):  # not a carried-over row
                log.warning("mo_house_pdf.failed", url=file_row.url, error=file_row.error)
            sink.add(file_row)
            sink.add(text_row)
            for ref in statute_refs(text_row):
                sink.add(ref)
    return sink.counts
