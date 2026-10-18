"""U.S. House Clerk financial disclosures (Ethics in Government Act): annual reports + periodic
transaction reports (stock trades) for Missouri members.

The yearly index (tab-delimited, national) lands verbatim. For Missouri members' e-filed reports the
PDF text is extracted line by line into `house_fd_pdf_lines`; dbt classifies the lines into assets,
income and transactions. Scanned paper filings (DocID 8xxxxxxx/9xxxxxxx) have no text layer and are
recorded with `has_text = false` so the gap is visible rather than silent.
"""

import io
import os
import zipfile
from datetime import date

import pdfplumber

from mogov import db
from mogov.http import fetch
from mogov.loaders import loader

BASE = "https://disclosures-clerk.house.gov/public_disc"
FIRST_YEAR = int(os.environ.get("MOGOV_HOUSE_FD_FIRST_YEAR", "2015"))
# Filing types worth reading: O original annual, A amendment, P periodic transaction report, C candidate, T termination.
PDF_TYPES = {"O", "A", "P", "C", "T"}


def _pdf_url(year: str, doc_id: str, filing_type: str) -> str:
    folder = "ptr-pdfs" if filing_type == "P" else "financial-pdfs"
    return f"{BASE}/{folder}/{year}/{doc_id}.pdf"


@loader("house_fd")
def load() -> dict[str, int]:
    index_rows, lines = [], []
    for year in range(FIRST_YEAR, date.today().year + 1):
        data = fetch(f"{BASE}/financial-pdfs/{year}FD.zip", max_age=86400 if year >= date.today().year - 1 else None)
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            txt = zf.read(f"{year}FD.txt").decode("utf-8-sig")
        header, *rows = [r.split("\t") for r in txt.splitlines() if r.strip()]
        for r in rows:
            rec = dict(zip(header, r, strict=False))
            rec["index_year"] = year
            index_rows.append((f"{year}/{rec.get('DocID')}", rec))

    for _, rec in index_rows:
        if not (rec.get("StateDst") or "").startswith("MO") or rec.get("FilingType") not in PDF_TYPES:
            continue
        url = _pdf_url(str(rec["Year"]), rec["DocID"], rec["FilingType"])
        try:
            pdf_bytes = fetch(url, max_age=None, delay=0.3)
        except Exception as exc:
            lines.append((url, {"doc_id": rec["DocID"], "url": url, "error": str(exc)}))
            continue
        with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
            texts = [(i, page.extract_text(layout=False) or "") for i, page in enumerate(pdf.pages, 1)]
        has_text = any(t.strip() for _, t in texts)
        if not has_text:
            lines.append((url, {"doc_id": rec["DocID"], "url": url, "has_text": False}))
            continue
        for page_no, text in texts:
            for line_no, line in enumerate(text.splitlines(), 1):
                if line.strip():
                    lines.append(
                        (
                            f"{url}#{page_no}.{line_no}",
                            {
                                "doc_id": rec["DocID"],
                                "url": url,
                                "has_text": True,
                                "page": page_no,
                                "line_no": line_no,
                                "text": line,
                            },
                        )
                    )
    return {
        "house_fd_index": db.replace_json("house_fd_index", index_rows, source_url=BASE),
        "house_fd_pdf_lines": db.replace_json("house_fd_pdf_lines", lines, source_url=BASE),
    }
