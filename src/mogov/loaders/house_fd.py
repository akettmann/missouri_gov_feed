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

from mogov import db, obs
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://disclosures-clerk.house.gov/public_disc"
FIRST_YEAR = int(os.environ.get("MOGOV_HOUSE_FD_FIRST_YEAR", "2015"))
# Filing types worth reading: O original annual, A amendment, P periodic transaction report, C candidate, T termination.
PDF_TYPES = {"O", "A", "P", "C", "T"}


def _pdf_url(year: str, doc_id: str, filing_type: str) -> str:
    folder = "ptr-pdfs" if filing_type == "P" else "financial-pdfs"
    return f"{BASE}/{folder}/{year}/{doc_id}.pdf"


def _index(year: int) -> list[dict]:
    data = fetch(f"{BASE}/financial-pdfs/{year}FD.zip", max_age=86400 if year >= date.today().year - 1 else None)
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        txt = zf.read(f"{year}FD.txt").decode("utf-8-sig")
    header, *rows = [r.split("\t") for r in txt.splitlines() if r.strip()]
    return [{**dict(zip(header, r, strict=False)), "index_year": year} for r in rows]


@loader("house_fd")
def load(shard: db.Shard) -> dict[str, int]:
    """Units: index years, and Missouri filings' PDFs (by URL). Every shard reads every index (cached) to
    find the Missouri filings."""
    pdfs: list[tuple[str, dict]] = []
    with db.JsonSink(shard, source_url=BASE, tables=["house_fd_index", "house_fd_pdf_lines"]) as sink:
        for year in range(FIRST_YEAR, date.today().year + 1):
            for rec in _index(year):
                if shard.owns(str(year)):
                    sink.add("house_fd_index", f"{year}/{rec.get('DocID')}", rec)
                if (rec.get("StateDst") or "").startswith("MO") and rec.get("FilingType") in PDF_TYPES:
                    pdfs.append((_pdf_url(str(rec["Year"]), rec["DocID"], rec["FilingType"]), rec))

        pdfs = shard.take(pdfs, key=lambda p: p[0])
        progress = obs.Progress("disclosure PDFs", len(pdfs), log)
        for url, rec in pdfs:
            progress.tick()
            try:
                pdf_bytes = fetch(url, max_age=None, delay=0.3)
            except Exception as exc:
                sink.add("house_fd_pdf_lines", url, {"doc_id": rec["DocID"], "url": url, "error": str(exc)})
                continue
            with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
                texts = [(i, page.extract_text(layout=False) or "") for i, page in enumerate(pdf.pages, 1)]
            if not any(t.strip() for _, t in texts):
                sink.add("house_fd_pdf_lines", url, {"doc_id": rec["DocID"], "url": url, "has_text": False})
                continue
            for page_no, text in texts:
                for line_no, line in enumerate(text.splitlines(), 1):
                    if line.strip():
                        sink.add(
                            "house_fd_pdf_lines",
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
        progress.finish()
    return sink.counts
