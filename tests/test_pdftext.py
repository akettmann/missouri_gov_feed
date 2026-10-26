from pathlib import Path

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
