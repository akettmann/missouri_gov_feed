"""Cached PDF text extraction. pdfplumber takes seconds per document and dominated re-runs of the PDF
loaders (~9 minutes per shard for the MO Senate journals even with every PDF cached). A PDF's text depends
only on its bytes and the extraction options, so the text is cached under that key."""

import hashlib
import io
import json
import time
from importlib.metadata import version
from pathlib import Path

import pdfplumber
from pdfplumber.utils import cluster_objects

from mogov.config import CACHE_DIR
from mogov.http import write_atomic

# part of the key, so upgrading pdfplumber (whose output can shift) re-extracts everything
EXTRACTOR = f"pdfplumber-{version('pdfplumber')}"


# One document may take this long to extract (checked between pages); a malformed or enormous PDF then becomes an
# error for that document instead of hanging a shard. A single page that never returns cannot be interrupted here.
MAX_SECONDS = 600.0


class ExtractTimeout(TimeoutError):
    """Extraction of one PDF ran past its time budget."""


def _key(data_digest, extract_opts: dict, max_pages: int | None) -> str:
    # max_pages joins the key only when set, so existing cache entries stay valid
    key = data_digest.copy()
    key.update(
        json.dumps([EXTRACTOR, extract_opts] + ([max_pages] if max_pages is not None else []), sort_keys=True).encode()
    )
    return key.hexdigest()


def _alias(sha256_hex: str, extract_opts: dict, max_pages: int | None) -> Path:
    """Tiny pointer file: (PDF sha256, options) -> the cache key. It lets a caller that already knows a PDF's hash
    reuse the cached text without reading the PDF (slow over a network mount) to derive the key."""
    blob = json.dumps([sha256_hex, EXTRACTOR, extract_opts, max_pages], sort_keys=True).encode()
    return CACHE_DIR / "pdftext" / "by-hash" / f"{hashlib.sha256(blob).hexdigest()}.key"


def cached_page_texts(sha256_hex: str, *, max_pages: int | None = None, **extract_opts) -> list[str] | None:
    """The cached page_texts() of the PDF with this sha256, or None when it is not cached (or not known by
    hash yet: an earlier page_texts() call on the bytes records that)."""
    try:
        key = _alias(sha256_hex, extract_opts, max_pages).read_text().strip()
        return json.loads((CACHE_DIR / "pdftext" / f"{key}.json").read_bytes())
    except (OSError, ValueError):
        return None


def page_texts(
    data: bytes, *, max_pages: int | None = None, max_seconds: float | None = MAX_SECONDS, **extract_opts
) -> list[str]:
    """page.extract_text(**extract_opts) for every page, or only the first `max_pages` ("" where a page has
    no text layer). Raises ExtractTimeout when the pages together take longer than `max_seconds` (None: no
    limit); each page's parsed objects are released before the next, so memory follows the largest page, not
    the document."""
    digest = hashlib.sha256(data)
    key = _key(digest, extract_opts, max_pages)
    path = CACHE_DIR / "pdftext" / f"{key}.json"
    alias = _alias(digest.hexdigest(), extract_opts, max_pages)
    if path.exists():
        if not alias.exists():
            write_atomic(alias, key.encode())
        return json.loads(path.read_bytes())
    deadline = None if max_seconds is None else time.monotonic() + max_seconds
    texts = []
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        for page in pdf.pages[:max_pages]:
            if deadline is not None and time.monotonic() > deadline:
                raise ExtractTimeout(f"text extraction ran past {max_seconds:g} s after {len(texts)} pages")
            texts.append(page.extract_text(**extract_opts) or "")
            page.close()  # drops the page's parsed objects and cached layout
    write_atomic(path, json.dumps(texts).encode())
    write_atomic(alias, key.encode())
    return texts


def page_lines(data: bytes, y_tolerance: float = 3) -> list[list[list[tuple[str, float]]]]:
    """Every page's text lines as [(word, x0), ...] left to right, for tables whose columns matter. Lines are
    words clustered by their top edge (the same grouping page.extract_text() uses, so a line's words joined by
    spaces equal its extract_text line). Cached like page_texts()."""
    key = hashlib.sha256(data)
    key.update(json.dumps([EXTRACTOR, "lines", y_tolerance]).encode())
    path = CACHE_DIR / "pdftext" / f"{key.hexdigest()}.json"
    if path.exists():
        return json.loads(path.read_bytes())
    pages = []
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        for page in pdf.pages:
            lines = cluster_objects(page.extract_words(), "top", y_tolerance)
            pages.append(
                [[(w["text"], round(w["x0"], 1)) for w in sorted(line, key=lambda w: w["x0"])] for line in lines]
            )
    write_atomic(path, json.dumps(pages).encode())
    return pages
