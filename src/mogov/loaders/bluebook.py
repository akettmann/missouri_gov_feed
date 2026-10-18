"""Missouri Official Manual ("Blue Book"), Secretary of State. Official biographies of statewide officers,
legislators and every state judge (career history, appointments, elections, term expirations).

Published as chapter PDFs every two years. Text is extracted line by line (with page numbers);
dbt splits it into per-person biographies and pulls out offices, appointments and legal careers.
"""

import io
import os
import re

import pdfplumber

from mogov import db, obs
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://www.sos.mo.gov"
EDITIONS = os.environ.get("MOGOV_BLUEBOOK_EDITIONS", "2025-2026").split(",")
CHAPTERS = {"2_Executive": "executive", "4_Legislative": "legislative", "5_Judicial": "judicial"}


def _chapter_urls(edition: str) -> dict[str, str]:
    """Chapter PDF links from the edition index page (file names differ between editions)."""
    html = fetch(f"{BASE}/bluebook/{edition}", max_age=30 * 86400).decode("utf-8", "replace")
    links = set(re.findall(r'href="([^"]+\.pdf)"', html, flags=re.I))
    found = {}
    for stem, chapter in CHAPTERS.items():
        for link in links:
            if stem.lower() in link.lower():
                found[chapter] = link if link.startswith("http") else BASE + link
    for stem, chapter in CHAPTERS.items():  # fall back to the 2019+ naming scheme
        found.setdefault(chapter, f"{BASE}/cmsimages/bluebook/{edition}/{stem}.pdf")
    return found


def _page_columns(page) -> list[str]:
    """Text of each column, left to right. The manual mixes one- and two-column pages; a page counts as
    two-column when (almost) no words straddle the vertical midline."""
    mid = page.width / 2
    words = page.extract_words()
    straddling = sum(1 for w in words if w["x0"] < mid - 2 and w["x1"] > mid + 2)
    if words and straddling <= 2:
        left = page.crop((0, 0, mid, page.height)).extract_text() or ""
        right = page.crop((mid, 0, page.width, page.height)).extract_text() or ""
        return [left, right]
    return [page.extract_text() or ""]


@loader("bluebook")
def load() -> dict[str, int]:
    lines = []
    for edition in EDITIONS:
        for chapter, url in _chapter_urls(edition.strip()).items():
            data = fetch(url, max_age=None, delay=0.5)
            if data[:4] != b"%PDF":
                log.warning("bluebook.not_pdf", edition=edition, chapter=chapter, url=url)
                continue
            with pdfplumber.open(io.BytesIO(data)) as pdf:
                for page_no, page in enumerate(pdf.pages, 1):
                    line_no = 0
                    for column, text in enumerate(_page_columns(page), 1):
                        for line in text.splitlines():
                            if line.strip():
                                line_no += 1
                                lines.append(
                                    (
                                        f"{edition}/{chapter}/{page_no}/{line_no}",
                                        {
                                            "edition": edition,
                                            "chapter": chapter,
                                            "page": page_no,
                                            "column": column,
                                            "line_no": line_no,
                                            "text": line,
                                            "url": url,
                                        },
                                    )
                                )
    return {"bluebook_lines": db.replace_json("bluebook_lines", lines, source_url=BASE)}
