"""Missouri Senate bill tracking (senate.mo.gov): every Senate bill of a session and its action history.

- BillTracking/Bills/BillList?year=YYYY&session=R is one page per session (3-6 MB). Its CSV button embeds the
  whole list as JSON in a script element (`const bills = [...];`): one object per Senate bill or resolution
  (SB, SJR, SCR, SR). The objects land as printed (the served `year` untouched), plus `list_year` (the year
  asked for) and
  `session_type`, one row per bill. Extraordinary sessions are `E1`, `E2`, ...;
  a session that doesn't exist comes back as `const bills = [];`.
- BillTracking/Bills/BillList?billId=N&year=YYYY&billPrefix=SB&billSuffix=1&handler=Actions is an HTML fragment
  with the bill's whole action history (Senate and House side, enrollment, governor), newest first, one table
  row per action: date, action text, journal reference and a link to the journal PDF page. One row per action.
- The same URL with handler=BillText, FiscalNotes, Amendments or Summaries is the bill page's other tabs: the
  list of text-version PDFs (LR number and version name), fiscal-note PDFs, amendments (each PDF is
  handler=AmendmentPdf&year=YYYY&amendmentId=N) and the summaries (the text is in the fragment). One row per
  link or summary, the link's fields as served; the PDFs themselves are not fetched here. CommitteeMinutes
  answers HTTP 500 and is left out (committee data is #280). MOGOV_SENATE_BILL_DOCS=0 skips these four.

`billId` is the site's own key, not the bill number (2025 SB 1 is 233; 2017 SB 1 is 57095344).

Every shard reads every session list (one request per session, then the shared cache), and takes the bills
whose key `year/session/billId` hashes to it, so the split doesn't depend on who else is running. A bill's
list row, action rows and document rows land in the same shard.
Requests to the host are paced by the lock shared by every process on the machine
(http.fetch min_interval): shards add no speed.
"""

import json
import os
import re
from datetime import date
from urllib.parse import parse_qs, urlparse

import lxml.html

from mogov import db, obs
from mogov.config import window_years
from mogov.http import fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

HOST = "www.senate.mo.gov"
BASE = f"https://{HOST}"
LIST_URL = f"{BASE}/BillTracking/Bills/BillList"
BILLS_TABLE = "mo_senate_bill_list"
ACTIONS_TABLE = "mo_senate_bill_actions"
TEXTS_TABLE = "mo_senate_bill_texts"
FISCAL_NOTES_TABLE = "mo_senate_bill_fiscal_notes"
AMENDMENTS_TABLE = "mo_senate_bill_amendments"
SUMMARIES_TABLE = "mo_senate_bill_summaries"
# handler -> (table, the fragment's container, the tab's own "none" notice). A bill with none of a kind gets
# "No <things> available for this bill." instead, also a real answer with zero rows. The notices are matched per
# tab (not any "No ... available"), so an error page such as "No content available" is not taken for one.
DOC_HANDLERS = {
    "BillText": (
        TEXTS_TABLE,
        b"bill-text-container",
        re.compile(rb"No (?:bill )?text(?: versions)? available", re.I),
    ),
    "FiscalNotes": (FISCAL_NOTES_TABLE, b"fiscal-notes-container", re.compile(rb"No fiscal notes available", re.I)),
    "Amendments": (AMENDMENTS_TABLE, b"amendments-container", re.compile(rb"No amendments available", re.I)),
    "Summaries": (SUMMARIES_TABLE, b"summaries-container", re.compile(rb"No summaries available", re.I)),
}
DOC_TABLES = [t for t, _, _ in DOC_HANDLERS.values()]
# The Actions tab: its container, or the notice a bill with no actions gets (HTTP 200, 81 bytes, seen live
# 2026-10: `<p ...>No actions found for this bill.</p>`).
ACTIONS_MARKER = b"actions-container"
ACTIONS_NONE = re.compile(rb"No actions (?:found|available) for this bill", re.I)
# senate.mo.gov accepted at ~1 request/second (#584). Every senate.mo.gov loader paces through host_throttle
# (http.fetch min_interval), a lock shared by all processes on the machine. On Cloud Run each task has its own
# filesystem, so the lock doesn't see the other tasks: each task slows down by the task count to keep the total.
POLITE_DELAY = 1.0
# Extraordinary sessions are probed as E1, E2, ... until one comes back empty (E4 is beyond any seen).
MAX_EXTRA_SESSIONS = 4
OPEN_MAX_AGE = 86400
CLOSED_MAX_AGE = 30 * 86400
# The list page's check: an error or block page served with 200 must not be cached as an (empty) list.
LIST_MARKER = b"const bills"

BILLS_ASSIGNMENT = re.compile(r"const\s+bills\s*=\s*")  # finds where the JSON starts in script text; json parses it


class NotABillFragment(RuntimeError):
    """A bill-page tab fragment that is neither a document list nor the site's "none available" notice."""


class NotABillList(RuntimeError):
    """A page asked for as a session's bill list that has no `const bills` array."""


def _is_bill_list(resp) -> None:
    if LIST_MARKER not in resp.content:
        raise NotABillList(f"no `const bills` in the response for {resp.url}")


def parse_bill_list(page: str) -> list[dict]:
    """A bill-list page -> the bill objects of its embedded `const bills = [...]` (empty when it has none)."""
    if not page.strip():
        return []
    root = lxml.html.fromstring(page)
    for script in root.iter("script"):
        text = script.text or ""
        if (m := BILLS_ASSIGNMENT.search(text)) is None:
            continue
        bills, _ = json.JSONDecoder().raw_decode(text, m.end())
        return [b for b in bills if isinstance(b, dict)]
    return []


def _is_doc_fragment(handler: str):
    """check= for a document tab: reject (so never cache) a body that is neither the tab's container nor the
    tab's own "No ... available" notice, e.g. an error or block page served with 200."""
    _, marker, none = DOC_HANDLERS[handler]

    def check(resp) -> None:
        if marker not in resp.content and not none.search(resp.content):
            raise NotABillFragment(f"not a {handler} fragment: {resp.url}")

    return check


def _is_actions_fragment(resp) -> None:
    """check= for the Actions tab: its container or its "none" notice, else an error or block page (not cached)."""
    if ACTIONS_MARKER not in resp.content and not ACTIONS_NONE.search(resp.content):
        raise NotABillFragment(f"not an Actions fragment: {resp.url}")


def _cell(td) -> str:
    return " ".join(td.text_content().split())


def parse_actions(fragment: str) -> list[dict]:
    """A bill's Actions fragment -> [{action_index, action_date, action, journal_ref, journal_url}] in the
    order served (newest first; action_index 0 is the top row). Text is as printed, whitespace collapsed."""
    if not fragment.strip():
        return []
    rows = []
    root = lxml.html.fromstring(fragment)
    for tr in root.xpath('//*[@id="actionsTable"]//tbody/tr'):
        tds = tr.findall("td")
        if len(tds) < 2:
            continue
        link = tds[2].find(".//a[@href]") if len(tds) > 2 else None
        rows.append(
            {
                "action_index": len(rows),
                "action_date": _cell(tds[0]),
                "action": _cell(tds[1]),
                "journal_ref": _cell(tds[2]) if len(tds) > 2 else "",
                "journal_url": link.get("href") if link is not None else None,
            }
        )
    return rows


def _text(el) -> str:
    return " ".join(el.text_content().split())


def _link_cards(fragment: str) -> list:
    if not fragment.strip():
        return []
    return lxml.html.fromstring(fragment).xpath('//*[contains(@class, "link-card-stack")]//a[@href]')


def parse_texts(fragment: str) -> list[dict]:
    """A BillText fragment -> [{doc_index, url, title, label, lr_number, version}] in served order. `label` is
    the link text as printed ("0453S.04T - Truly Agreed to and Finally Passed"); lr_number and version are its
    two halves (version is the whole label when there is no " - ")."""
    rows = []
    for a in _link_cards(fragment):
        label = _text(a)
        lr, sep, version = label.partition(" - ")
        rows.append(
            {
                "doc_index": len(rows),
                "url": a.get("href"),
                "title": a.get("title"),
                "label": label,
                "lr_number": lr if sep else None,
                "version": version if sep else label,
            }
        )
    return rows


def parse_fiscal_notes(fragment: str) -> list[dict]:
    """A FiscalNotes fragment -> [{doc_index, url, title, label}] in served order; label is the link text as
    printed ("Perfected (0453S.04P.ORG)")."""
    return [
        {"doc_index": i, "url": a.get("href"), "title": a.get("title"), "label": _text(a)}
        for i, a in enumerate(_link_cards(fragment))
    ]


def parse_amendments(fragment: str) -> list[dict]:
    """An Amendments fragment -> [{doc_index, amendment_id, url, title, label, status}] in served order. label
    is the link text ("2/4/2025 - SS S offered & adopted (Crawford)--(0453S.04F)"), status the chip beside it
    ("2/4/2025 - Adopted", None when absent), amendment_id the `amendmentId` of the PDF url."""
    rows = []
    for a in _link_cards(fragment):
        chip = a.xpath('.//*[contains(@class, "square-status-chip")]')
        label_el = a.find("span")
        ids = parse_qs(urlparse(a.get("href")).query).get("amendmentId")
        rows.append(
            {
                "doc_index": len(rows),
                "amendment_id": int(ids[0]) if ids and ids[0].isdigit() else None,
                "url": a.get("href"),
                "title": a.get("title"),
                "label": _text(label_el if label_el is not None else a),
                "status": _text(chip[0]) if chip else None,
            }
        )
    return rows


def parse_summaries(fragment: str) -> list[dict]:
    """A Summaries fragment -> [{doc_index, summary_id, label, text}] in served order. label is the version
    heading ("Introduced"); text is the summary exactly as printed (line breaks and tabs kept)."""
    if not fragment.strip():
        return []
    rows = []
    for card in lxml.html.fromstring(fragment).xpath("//*[@data-summary-id]"):
        body = card.xpath('.//*[contains(@class, "text-content--preformatted")]')
        heading = card.xpath('.//*[contains(@class, "heading--label")]')
        rows.append(
            {
                "doc_index": len(rows),
                "summary_id": int(card.get("data-summary-id")),
                "label": _text(heading[0]) if heading else None,
                "text": body[0].text_content() if body else "",
            }
        )
    return rows


DOC_PARSERS = {
    "BillText": parse_texts,
    "FiscalNotes": parse_fiscal_notes,
    "Amendments": parse_amendments,
    "Summaries": parse_summaries,
}


def docs_enabled() -> bool:
    return os.environ.get("MOGOV_SENATE_BILL_DOCS", "1").strip().lower() not in {"0", "false", "no", "off"}


def senate_interval() -> float:
    """Seconds between requests to senate.mo.gov for min_interval; shared by mo_senate, mo_senate_topics and here."""
    return POLITE_DELAY * int(os.environ.get("CLOUD_RUN_TASK_COUNT") or 1)


def _max_age(year: int) -> float:
    # the open session's list and histories change daily; a past one only with late corrections
    return OPEN_MAX_AGE if year >= date.today().year else CLOSED_MAX_AGE


def _get(params: dict, year: int, **kw) -> str:
    return fetch(LIST_URL, params, max_age=_max_age(year), min_interval=senate_interval(), **kw).decode(
        "utf-8", "replace"
    )


def session_lists(year: int) -> list[tuple[str, list[dict]]]:
    """[(session, bills)] of a year: R, then E1, E2, ... until one has no bills."""
    found = []
    for session in ["R", *(f"E{n}" for n in range(1, MAX_EXTRA_SESSIONS + 1))]:
        bills = parse_bill_list(_get({"year": year, "session": session}, year, check=_is_bill_list))
        if not bills:
            if session == "R":
                log.warning("mo_senate_bills.empty_list", year=year, session=session)
                continue  # an empty regular session says nothing about E1
            break
        found.append((session, bills))
    return found


def bill_key(year: int, session: str, bill_id: int) -> str:
    return f"{year}/{session}/{bill_id}"


def bill_label(bill: dict) -> str:
    return f"{bill.get('billPrefix', '')}{bill.get('billSuffix', '')}"


def _actions_params(year: int, bill: dict) -> dict:
    return {
        "billId": bill["billId"],
        "year": year,
        "billPrefix": bill.get("billPrefix", ""),
        "billSuffix": bill.get("billSuffix", ""),
        "handler": "Actions",
    }


def _doc_params(year: int, session: str, bill: dict, handler: str) -> dict:
    params = {**_actions_params(year, bill), "handler": handler}
    if handler == "FiscalNotes":
        # The tab's own script sends it, but the list page's data-modal-url does not; the response is identical
        # either way (probed 2026-10-26). Sent to match the tab.
        params["sessionType"] = session
    return params


def owned_bills(shard: db.Shard, lists: list[tuple[int, str, list[dict]]]) -> list[tuple[int, str, dict]]:
    """The (year, session, bill) units this shard owns; each bill once, whichever shards are running."""
    seen: set[str] = set()
    units = []
    for year, session, bills in lists:
        for b in bills:
            key = bill_key(year, session, b["billId"])
            if key in seen:  # a list that repeats a bill
                continue
            seen.add(key)
            if shard.owns(key):
                units.append((year, session, b))
    return units


@loader("mo_senate_bills", service=HOST)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: the session lists (read by every shard, one request each), then one unit per bill."""
    lists = []
    for year in window_years():
        for session, bills in session_lists(year):
            log.info("mo_senate_bills.session", year=year, session=session, bills=len(bills))
            lists.append((year, session, bills))
    units = owned_bills(shard, lists)
    docs = docs_enabled()
    tables = [BILLS_TABLE, ACTIONS_TABLE, *(DOC_TABLES if docs else [])]
    with db.JsonSink(shard, source_url=LIST_URL, tables=tables) as sink:
        progress = obs.Progress("bills", len(units), log)
        for year, session, bill in units:
            key = bill_key(year, session, bill["billId"])
            params = _actions_params(year, bill)
            url = f"{LIST_URL}?" + "&".join(f"{k}={v}" for k, v in params.items())
            # Fetch every fragment before landing any row, so a rejected one skips the whole bill for this run
            # (nothing cached, retried next run) instead of crashing the shard or landing a partial bill.
            try:
                actions = parse_actions(_get(params, year, check=_is_actions_fragment))
                fetched = []
                for handler in DOC_HANDLERS if docs else ():
                    dparams = _doc_params(year, session, bill, handler)
                    fragment = _get(dparams, year, check=_is_doc_fragment(handler))
                    durl = f"{LIST_URL}?" + "&".join(f"{k}={v}" for k, v in dparams.items())
                    fetched.append((handler, DOC_PARSERS[handler](fragment), durl))
            except NotABillFragment as e:
                log.warning("mo_senate_bills.fragment_rejected", year=year, session=session, bill_key=key, error=str(e))
                progress.tick()
                continue
            sink.add(
                BILLS_TABLE,
                key,
                {**bill, "list_year": year, "session_type": session},
                source_url=f"{LIST_URL}?year={year}&session={session}",
            )
            if not actions:
                log.warning("mo_senate_bills.no_actions", year=year, session=session, bill_id=bill["billId"])
            for a in actions:
                row = {
                    "year": year,
                    "session_type": session,
                    "bill_id": bill["billId"],
                    "bill": bill_label(bill),
                    **a,
                }
                sink.add(ACTIONS_TABLE, f"{key}/{a['action_index']}", row, source_url=url)
            for handler, parsed, durl in fetched:
                table = DOC_HANDLERS[handler][0]
                for d in parsed:
                    row = {
                        "year": year,
                        "session_type": session,
                        "bill_id": bill["billId"],
                        "bill": bill_label(bill),
                        **d,
                    }
                    sink.add(table, f"{key}/{d['doc_index']}", row, source_url=durl)
            progress.tick()
        progress.finish()
    return sink.counts
