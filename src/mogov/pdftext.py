"""Cached PDF text extraction. pdfplumber takes seconds per document and dominated re-runs of the PDF
loaders (~9 minutes per shard for the MO Senate journals even with every PDF cached). A PDF's text depends
only on its bytes and the extraction options, so the text is cached under that key."""

import hashlib
import io
import json
from importlib.metadata import version

import pdfplumber

from mogov.config import CACHE_DIR
from mogov.http import write_atomic

# part of the key, so upgrading pdfplumber (whose output can shift) re-extracts everything
_EXTRACTOR = f"pdfplumber-{version('pdfplumber')}"


def page_texts(data: bytes, **extract_opts) -> list[str]:
    """page.extract_text(**extract_opts) for every page ("" where a page has no text layer)."""
    key = hashlib.sha256(data)
    key.update(json.dumps([_EXTRACTOR, extract_opts], sort_keys=True).encode())
    path = CACHE_DIR / "pdftext" / f"{key.hexdigest()}.json"
    if path.exists():
        return json.loads(path.read_bytes())
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        texts = [page.extract_text(**extract_opts) or "" for page in pdf.pages]
    write_atomic(path, json.dumps(texts).encode())
    return texts
