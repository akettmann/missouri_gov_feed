"""Missouri Secretary of State official election returns (https://www.sos.mo.gov/elections/results).

One statewide "Grand Totals" PDF per general and primary election, Aug 2012 onward, listed on the results
page. Every printed line lands as one raw row with the PDF URL, the page and the line position; structure-level
facts only (which contest a line belongs to, and the table cells of a candidate row, split by the PDF's column
positions). Everything else (precinct counts, write-in flags, party names, retention) is dbt's.

Not loaded: the presidential preference primaries (a different layout: "Last, First", party codes, no party
column; the 2020 PDF has no text layer), the single-district special-election PDFs, the by-county PDFs and the
1996-2011 results (a different page, not verified). Election Night Reporting (enr.sos.mo.gov) has no downloads.
"""

import re
from datetime import date, datetime

from mogov import db, obs, pdftext
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

HOST = "www.sos.mo.gov"
RESULTS_URL = f"https://{HOST}/elections/results"
POLITE_DELAY = 2.0
ELECTION_TYPES = {
    "General Election": "general",
    "Primary Election": "primary",
}
# Section headings of the results page, and the "Grand Totals" links under them.
_HEADING = re.compile(
    r"((?:General|Primary|Special|Presidential Preference Primary)\b[A-Za-z ]*?)\s+-\s+([A-Z][a-z]+ \d{1,2}, \d{4})"
)
_GRAND_TOTALS = re.compile(r'<a\s+[^>]*href="([^"]+\.pdf)"[^>]*>\s*Grand Totals\s*</a>', re.I)
CANDIDATE_ROW = re.compile(r"^[\d,]+ \d+(?:\.\d+)?%$")
# Header words give the party column's left edge; the name column ends well before it (name text ends by
# x=230, party text starts at x=258 in the 2012 and 2024 files), so the boundary sits 30 points left of the
# "Party" header (x=274).
PARTY_OFFSET = 30
DEFAULT_PARTY_X = 244.0


def elections(page_html: str) -> list[dict]:
    """The statewide Grand Totals PDFs on the results page, oldest to newest: {key, type, date, url}."""
    out, current = {}, None
    # walk headings (plain text) and Grand Totals anchors in document order
    for m in re.finditer(_HEADING.pattern + "|" + _GRAND_TOTALS.pattern, page_html, re.I):
        if m.group(1) and m.group(2):
            kind = m.group(1).strip()
            current = (ELECTION_TYPES.get(kind), datetime.strptime(m.group(2), "%B %d, %Y").date())
        elif m.group(3) and current and current[0]:
            url = m.group(3)
            url = "https:" + url if url.startswith("//") else url
            etype, edate = current
            out[f"{edate.isoformat()}-{etype}"] = {
                "key": f"{edate.isoformat()}-{etype}",
                "type": etype,
                "date": edate,
                "url": url,
            }
    return sorted(out.values(), key=lambda e: e["key"])


def party_x(pages: list) -> float:
    """Left edge of the party column, from the 'Party' word of the table header on the first page."""
    for line in pages[0] if pages else []:
        for word, x0 in line:
            if word == "Party":
                return x0 - PARTY_OFFSET
    return DEFAULT_PARTY_X


def parse_pdf(pages: list) -> list[dict]:
    """One dict per printed line: page, line (1-based), text, kind, contest_seq and (candidate rows) cells.

    kind: 'header' (a contest title with "(n of n Precincts Reported)"), 'candidate' (ends with votes and %),
    'total' ("Total Votes ..."), 'party_total' (a party's subtotal in a primary), 'other' (title block, page
    furniture, and rows in layouts not parsed: the older "Ballot Issue Yes: n" lines and the presidential
    preference primaries). contest_seq counts headers from 1; lines
    before the first header have 0. cells = {name, party, votes, pct}: the words left of the party column,
    the words in it, then the last two words.
    """
    boundary = party_x(pages)
    rows, seq = [], 0
    for p, lines in enumerate(pages, 1):
        for n, words in enumerate(lines, 1):
            text = " ".join(w for w, _ in words)
            row = {"page": p, "line": n, "text": text, "contest_seq": seq}
            if "Precincts Reported)" in text:
                seq += 1
                row |= {"kind": "header", "contest_seq": seq}
            elif text.startswith("Total Votes"):
                row["kind"] = "total"
            elif text.startswith("Party Total"):
                row["kind"] = "party_total"
            elif len(words) >= 3 and CANDIDATE_ROW.match(f"{words[-2][0]} {words[-1][0]}"):
                body = words[:-2]
                row["kind"] = "candidate"
                row["cells"] = {
                    "name": " ".join(w for w, x in body if x < boundary),
                    "party": " ".join(w for w, x in body if x >= boundary),
                    "votes": words[-2][0],
                    "pct": words[-1][0],
                }
            else:
                row["kind"] = "other"
            rows.append(row)
    return rows


def _election_rows(election: dict, rows: list[dict]):
    for r in rows:
        key = f"{election['key']}#{r['page']:03d}.{r['line']:04d}"
        yield (
            key,
            {
                "election_key": election["key"],
                "election_type": election["type"],
                "election_date": election["date"],
                "pdf_url": election["url"],
                **r,
            },
        )


@loader("mo_sos_elections", service=HOST)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: elections (one Grand Totals PDF each), listed from the results page. PDFs are fetched one at a
    time with a delay; a closed election's PDF never changes after the canvass, the latest is re-checked daily."""
    listing = elections(fetch(RESULTS_URL, max_age=86400, delay=POLITE_DELAY).decode("utf-8", "replace"))
    mine = shard.take(listing, key=lambda e: e["key"])
    log.info("mo_sos_elections.elections", listed=len(listing), mine=len(mine))
    progress = obs.Progress("election PDFs", len(mine), log)
    with db.JsonSink(shard, source_url=RESULTS_URL, tables=["mo_sos_election_rows"]) as sink:
        for election in mine:
            recent = (date.today() - election["date"]).days < 120
            data = fetch(election["url"], max_age=86400 if recent else None, delay=POLITE_DELAY)
            if data[:4] != b"%PDF":
                raise ValueError(f"{election['url']} is not a PDF")
            rows = parse_pdf(pdftext.page_lines(data))
            for key, payload in _election_rows(election, rows):
                sink.add("mo_sos_election_rows", key, payload, source_url=election["url"])
            progress.tick()
            log.info("mo_sos_elections.parsed", election=election["key"], lines=len(rows))
        progress.finish()
    return sink.counts
