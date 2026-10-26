"""Missouri State Auditor audit reports and their performance ratings (auditor.mo.gov).

The Reports page is backed by a JSON list, /AuditReport/SearchAudits. An unfiltered call returns exactly 1,000
rows (the newest), so the loader asks one calendar year at a time (about 100-150 reports each, 1999 to now)
and lands every record verbatim in `mo_auditor_reports`.

The rating is printed in the report, not in the list: the one-page "Citizens Summary" PDF (and the same page
inside the full report) says "In the areas audited, the overall performance of this entity was Good." Since
2012 most audits link a summary PDF (`citz_sum_fk`); many others (statewide offices among them, e.g. the
Lieutenant Governor in 2026) have only the full PDF, whose first pages carry the same summary. The sentence is
looked for there and landed verbatim in `mo_auditor_ratings` with its provenance (PDF url, page); a PDF that
was read but had no sentence lands with `rating_sentence` null so the extraction rate is measurable. Routine
filings that are never rated (county "Financial Statements", the monthly filing reports, follow-up reports) are
not downloaded. Pre-2012 reports have only an HTML "yellow sheet" with no rating and are not read.

The ratings cover only the areas audited; a county's rating is the county's, not any one official's.
Units: reports (by report number), so shards split the PDF downloads; every shard lists the years itself.
"""

import json
import os
import re
from datetime import date

import httpx

from mogov import db, obs, pdftext
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://auditor.mo.gov"
SEARCH_URL = f"{BASE}/AuditReport/SearchAudits"
CITIZENS_SUMMARY_URL = f"{BASE}/AuditReport/CitzSummaryDirect"
FIRST_YEAR = int(os.environ.get("MOGOV_AUDITOR_FROM_YEAR", "1999"))
LAST_YEAR = int(os.environ.get("MOGOV_AUDITOR_TO_YEAR", str(date.today().year)))
# the rating scale starts in 2011 and the earliest summaries in the list are from 2012
FIRST_RATED_YEAR = 2012
SCAN_PAGES = 4  # the summary sits on page 1-2 of a full report (page 1 is a cover)
# Minimum seconds between two requests to auditor.mo.gov from ALL shards on this machine (http.host_throttle), so
# --shards N still sends about 1 request a second in total
DELAY = float(os.environ.get("MOGOV_AUDITOR_DELAY", "1.0"))

TABLES = ["mo_auditor_reports", "mo_auditor_ratings"]

# pdfplumber sometimes splits a word in this sentence ("In the areas au dited"), so spaces are optional between
# every pair of letters; the rating word is read up to the full stop (or the footnote asterisk) and unspaced
_PHRASE = "in the areas audited, the overall performance of this entity was"
RATING_SENTENCE = re.compile(
    r"\s*".join(",?" if c == "," else re.escape(c) for c in _PHRASE if c != " ")
    + r"\s*([A-Za-z][A-Za-z ]{1,14}?)\s*[.*]",
    re.I,
)
# Titles of filings that carry no rating: checked against the 2012-2026 reports that have a summary. The county-wide
# fire-district reviews are anchored to Greene / St. Louis so a single '<X> County Fire Protection District' is read
NOT_RATED = re.compile(
    r"financial statements?|monthly report|follow[\s-]*up|"
    r"annual (?:comprehensive )?(?:financial )?report|compilation|property tax|"
    r"^(?:greene|st\.? louis) county fire protection districts?\b|independent audits of fire protection|"
    r"forfeiture|working capital revolving",
    re.I,
)


def report_number(rec: dict) -> str:
    """'2018063   ' -> '2018063'."""
    return rec["rpt_number"].strip()


def extract_rating(page_texts: list[str]) -> dict:
    """The first 'overall performance of this entity was X' sentence in a PDF's page texts (whitespace is
    collapsed, so a sentence that wraps over lines still matches).

    -> {rating_sentence, rating_word, page (1-based), n_sentences}; the first three are None if there is none.
    """
    found = []
    for number, text in enumerate(page_texts, start=1):
        flat = re.sub(r"\s+", " ", text)
        for m in RATING_SENTENCE.finditer(flat):
            found.append((number, m.group(0).strip(), m.group(1).replace(" ", "")))
    if not found:
        return {"rating_sentence": None, "rating_word": None, "page": None, "n_sentences": 0}
    page, sentence, word = found[0]
    return {"rating_sentence": sentence, "rating_word": word, "page": page, "n_sentences": len(found)}


def rating_source(rec: dict) -> tuple[str, str] | None:
    """Where to look for this report's rating -> (kind, pdf url), or None when it is not worth fetching."""
    year = int(report_number(rec)[:4])
    if rec.get("citz_sum_fk"):
        return "citizens_summary", f"{CITIZENS_SUMMARY_URL}?id={rec['citz_sum_fk']}"
    link = rec.get("full_rpt_link") or ""
    if year < FIRST_RATED_YEAR or NOT_RATED.search(rec["title"]) or not link.lower().endswith(".pdf"):
        return None
    if link.startswith("~/"):
        link = BASE + link[1:]
    return "full_report", link


def list_year(year: int) -> list[dict]:
    max_age = 6 * 3600 if year >= date.today().year else 7 * 86400  # the open year gains reports weekly
    body = fetch(
        SEARCH_URL,
        {"SearchYearStart": year, "SearchYearEnd": year, "page": 0, "size": 1000},
        max_age=max_age,
        min_interval=DELAY,
    )
    doc = json.loads(body)
    rows = doc["data"]
    if len(rows) != doc["numTotalRecords"] or len(rows) >= 1000:
        raise RuntimeError(f"mo_auditor: {year} returned {len(rows)} of {doc['numTotalRecords']} (1,000-row cap?)")
    return rows


def read_rating(kind: str, url: str) -> dict:
    row = {"source_kind": kind, "pdf_url": url}
    try:
        pdf = fetch(url, max_age=None, min_interval=DELAY)
        pages = pdftext.page_texts(pdf, max_pages=SCAN_PAGES)
    except httpx.HTTPStatusError as e:
        return {**row, "status": f"http_{e.response.status_code}", **extract_rating([])}
    except Exception as e:  # a corrupt PDF must not stop the run; it lands as unreadable
        log.warning("mo_auditor.unreadable_pdf", url=url, error=repr(e))
        return {**row, "status": "unreadable", **extract_rating([])}
    found = extract_rating(pages)
    return {**row, "status": "ok" if found["rating_sentence"] else "no_rating_sentence", **found}


@loader("mo_auditor", service="auditor.mo.gov")
def load(shard: db.Shard) -> dict[str, int]:
    reports = []
    for year in range(FIRST_YEAR, LAST_YEAR + 1):
        reports += [(year, r) for r in list_year(year)]
    mine = [(y, r) for y, r in reports if shard.owns(report_number(r))]
    log.info("mo_auditor.listed", reports=len(reports), owned=len(mine))
    with db.JsonSink(shard, source_url=SEARCH_URL, tables=TABLES) as sink:
        progress = obs.Progress("audit reports", len(mine), log)
        for year, rec in mine:
            number = report_number(rec)
            sink.add("mo_auditor_reports", number, {"search_year": year, **rec})
            source = rating_source(rec)
            if source:
                kind, url = source
                sink.add(
                    "mo_auditor_ratings",
                    number,
                    {"report_number": number, **read_rating(kind, url)},
                    source_url=url,
                )
            progress.tick()
        progress.finish()
    return sink.counts
