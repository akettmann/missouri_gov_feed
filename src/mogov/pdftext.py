"""Cached PDF text extraction. pdfplumber takes seconds per document and dominated re-runs of the PDF
loaders (~9 minutes per shard for the MO Senate journals even with every PDF cached). A PDF's text depends
only on its bytes and the extraction options, so the text is cached under that key."""

import hashlib
import io
import json
from importlib.metadata import version

import pdfplumber
from pdfplumber.utils import cluster_objects

from mogov.config import CACHE_DIR
from mogov.http import write_atomic

# part of the key, so upgrading pdfplumber (whose output can shift) re-extracts everything
_EXTRACTOR = f"pdfplumber-{version('pdfplumber')}"


def page_texts(data: bytes, *, max_pages: int | None = None, **extract_opts) -> list[str]:
    """page.extract_text(**extract_opts) for every page, or only the first `max_pages` ("" where a page has
    no text layer)."""
    key = hashlib.sha256(data)
    # max_pages joins the key only when set, so existing cache entries stay valid
    key.update(json.dumps([_EXTRACTOR, extract_opts] + ([max_pages] if max_pages else []), sort_keys=True).encode())
    path = CACHE_DIR / "pdftext" / f"{key.hexdigest()}.json"
    if path.exists():
        return json.loads(path.read_bytes())
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        texts = [page.extract_text(**extract_opts) or "" for page in pdf.pages[:max_pages]]
    write_atomic(path, json.dumps(texts).encode())
    return texts


def page_lines(data: bytes, y_tolerance: float = 3) -> list[list[list[tuple[str, float]]]]:
    """Every page's text lines as [(word, x0), ...] left to right, for tables whose columns matter. Lines are
    words clustered by their top edge (the same grouping page.extract_text() uses, so a line's words joined by
    spaces equal its extract_text line). Cached like page_texts()."""
    key = hashlib.sha256(data)
    key.update(json.dumps([_EXTRACTOR, "lines", y_tolerance]).encode())
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
