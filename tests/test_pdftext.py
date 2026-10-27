import hashlib
from pathlib import Path

import pytest

from mogov import pdftext

ONE_PAGE = (Path(__file__).parent / "fixtures" / "mo_auditor_citizens_summary_676.pdf").read_bytes()


def _pdf(texts: list[str]) -> bytes:
    """A minimal PDF with one page per text (hand-built so no PDF writer is needed)."""
    n = len(texts)
    kids = " ".join(f"{3 + 2 * i} 0 R" for i in range(n))
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", f"<< /Type /Pages /Kids [{kids}] /Count {n} >>".encode()]
    for i, text in enumerate(texts):
        objs.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] /Contents {4 + 2 * i} 0 R "
            "/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>".encode()
        )
        stream = f"BT /F1 12 Tf 20 50 Td ({text}) Tj ET".encode()
        objs.append(f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream")
    out = b"%PDF-1.4\n"
    offsets = []
    for i, body in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    return out + f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode()


def test_max_pages_zero_is_its_own_cache_entry_not_the_full_document(tmp_path, monkeypatch):
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path)
    assert pdftext.page_texts(ONE_PAGE, max_pages=0) == []
    full = pdftext.page_texts(ONE_PAGE)
    assert full and full[0]  # a stale [] under the full-document key would be returned here
    assert pdftext.page_texts(ONE_PAGE, max_pages=0) == []
    assert len(list((tmp_path / "pdftext").glob("*.json"))) == 2


def test_max_pages_reads_only_the_first_pages(tmp_path, monkeypatch):
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path)
    pdf = _pdf(["alpha", "beta", "gamma"])
    assert pdftext.page_texts(pdf) == ["alpha", "beta", "gamma"]
    assert pdftext.page_texts(pdf, max_pages=2) == ["alpha", "beta"]
    assert pdftext.page_texts(pdf, max_pages=2) == ["alpha", "beta"]  # from cache, under its own key
    assert pdftext.page_texts(pdf, max_pages=0) == []


def test_cached_text_is_found_by_the_pdf_hash_without_the_pdf(tmp_path, monkeypatch):
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path)
    pdf = _pdf(["alpha", "beta"])
    digest = hashlib.sha256(pdf).hexdigest()
    assert pdftext.cached_page_texts(digest, layout=False) is None  # not extracted yet
    assert pdftext.page_texts(pdf, layout=False) == ["alpha", "beta"]
    assert pdftext.cached_page_texts(digest, layout=False) == ["alpha", "beta"]
    assert pdftext.cached_page_texts(digest, layout=True) is None  # options are part of the key
    assert pdftext.cached_page_texts(digest, layout=False, max_pages=1) is None


def test_old_cache_entries_gain_their_hash_pointer_on_first_use(tmp_path, monkeypatch):
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path)
    pdf = _pdf(["alpha"])
    pdftext.page_texts(pdf)
    for alias in (tmp_path / "pdftext" / "by-hash").glob("*.key"):
        alias.unlink()  # a cache written before pointers existed
    digest = hashlib.sha256(pdf).hexdigest()
    assert pdftext.cached_page_texts(digest) is None
    assert pdftext.page_texts(pdf) == ["alpha"]  # cache hit, pointer written
    assert pdftext.cached_page_texts(digest) == ["alpha"]


def test_extraction_past_its_time_budget_raises_and_caches_nothing(tmp_path, monkeypatch):
    monkeypatch.setattr(pdftext, "CACHE_DIR", tmp_path)
    pdf = _pdf(["alpha", "beta", "gamma"])
    clock = iter(range(0, 1000, 10))
    with monkeypatch.context() as mp:
        mp.setattr(pdftext.time, "monotonic", lambda: next(clock))
        with pytest.raises(pdftext.ExtractTimeout):
            pdftext.page_texts(pdf, max_seconds=15)
    assert not list((tmp_path / "pdftext").glob("*.json"))
    assert pdftext.page_texts(pdf, max_seconds=None) == ["alpha", "beta", "gamma"]
