"""Missouri Ethics Commission (www.mec.mo.gov): current campaign finance, candidate<->committee crosswalk,
and lobbyist expenditures (gifts) to public officials. Fills in what the TAP mirror lacks after 2022.

OPT-IN (MOGOV_MEC_OPT_IN=1). Read before enabling:
  * MEC's robots.txt disallows crawlers on these export pages (CF_ContrCSV.aspx, Lob_ExpCSV.aspx...).
    They're public tools for downloading public records, but automated use is against the site's stated
    crawler policy. Consider asking MEC (helpdesk@mec.mo.gov) first.
  * The site sits behind Imperva/Incapsula, which rejects non-browser User-Agents. This loader sends the
    pipeline's honest User-Agent unless you set MOGOV_MEC_USER_AGENT yourself.
Requests are serial with PAUSE-second gaps. Every export is cached (current year weekly, past years
monthly), so a re-run only goes back to MEC for what has gone stale. Each shard keeps its own pace, so
N shards make N times the request rate: keep --shards small for this loader.

The pages are ASP.NET WebForms: every postback must carry the __VIEWSTATE of the page it came from.
An export answers with a file, not a page, so the form keeps the last real page to post back from.

Personal financial disclosure statements (PFDs) are NOT online: MEC releases them only on written
Sunshine Law (RSMo 610) request, so they're not loaded here.
"""

import html
import json
import os
import re
import time
from datetime import date
from pathlib import Path

import httpx

from mogov import db, obs
from mogov.config import CACHE_DIR, USER_AGENT
from mogov.http import write_atomic
from mogov.loaders import loader

log = obs.get_logger(__name__)

BASE = "https://www.mec.mo.gov/MEC"
P = "ctl00$ctl00$ContentPlaceHolder$ContentPlaceHolder1$"
YEARS = [int(y) for y in os.environ.get("MOGOV_MEC_YEARS", "2023,2024,2025,2026").split(",")]
# Elections whose candidate<->committee lists to pull. Wider than YEARS: officials elected years ago still
# raise money through the committee they registered then. The election search only offers 2020 onward.
CROSSWALK_YEARS = [int(y) for y in os.environ.get("MOGOV_MEC_CROSSWALK_YEARS", "2020,2022,2024,2026").split(",")]
# report types: itemized contributions received, contributions made, itemized expenditures, report summaries
REPORT_TYPES = os.environ.get("MOGOV_MEC_REPORT_TYPES", "CD1_A,CD3_C,CD3_B,summary").split(",")
LOBBYING_FROM = "01/01/2019"
PAUSE = float(os.environ.get("MOGOV_MEC_PAUSE", "3.0"))
CACHE = CACHE_DIR / "mec"


class _Form:
    def __init__(self, client: httpx.Client, url: str):
        self.client, self.url = client, url
        self.page = self._send(None)

    def _send(self, data: dict | None) -> httpx.Response:
        time.sleep(PAUSE)
        started = time.perf_counter()
        if data is None:
            resp = self.client.get(self.url)
        else:
            resp = self.client.post(self.url, data=data, headers={"Referer": self.url})
        resp.raise_for_status()
        log.debug(
            "mec.request",
            page=self.url.rsplit("/", 1)[-1],
            target=(data or {}).get("__EVENTTARGET", "").removeprefix(P) or None,
            seconds=round(time.perf_counter() - started, 2),
            bytes=len(resp.content),
        )
        if "Incapsula" in resp.text[:2000]:
            raise RuntimeError(f"MEC bot protection rejected the request for {self.url}")
        if "__VIEWSTATE" in resp.text[:200_000]:
            self.page = resp  # a postable page; exports (CSV / Excel-HTML) aren't
        return resp

    def fields(self) -> dict[str, str]:
        t = self.page.text
        f = {}
        for m in re.finditer(r"<input([^>]*)>", t):
            a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
            if a.get("type") in ("hidden", "text") and "name" in a:
                f[html.unescape(a["name"])] = html.unescape(a.get("value", ""))
        for m in re.finditer(r'<select name="([^"]+)"([^>]*)>(.*?)</select>', t, re.S):
            if "disabled" in m.group(2):
                continue
            opt = re.search(r'selected="selected" value="([^"]*)"', m.group(3)) or re.search(
                r'value="([^"]*)"', m.group(3)
            )
            f[html.unescape(m.group(1))] = html.unescape(opt.group(1)) if opt else ""
        return f

    def set(self, name: str, value: str, postback: bool) -> None:
        f = self.fields()
        f[P + name] = value
        if postback:
            f["__EVENTTARGET"] = P + name
            self._send(f)

    def submit(self, button: str, label: str, extra: dict | None = None) -> httpx.Response:
        f = self.fields()
        f.update({P + k: v for k, v in (extra or {}).items()})
        f["__EVENTTARGET"] = ""
        f[P + button] = label
        return self._send(f)


def _client() -> httpx.Client:
    ua = os.environ.get("MOGOV_MEC_USER_AGENT", USER_AGENT)
    return httpx.Client(headers={"User-Agent": ua}, follow_redirects=True, timeout=httpx.Timeout(600, connect=30))


def _fresh(path: Path, year: int) -> bool:
    # current year: weekly; past years: monthly, so amendments filed after year-end still arrive
    max_age = 7 * 86400 if year >= date.today().year else 30 * 86400
    return path.exists() and time.time() - path.stat().st_mtime < max_age


def _write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(path, content)


class _Exports:
    """Lazily opened MEC session; most runs find everything cached and never connect."""

    def __init__(self):
        self._client: httpx.Client | None = None
        self.progress: obs.Progress | None = None

    @property
    def client(self) -> httpx.Client:
        if self._client is None:
            self._client = _client()
        return self._client

    def close(self) -> None:
        if self._client is not None:
            self._client.close()

    def contributions(self, rtype: str, years: list[int]) -> list[Path]:
        """One CSV per year. One form session per report type: after the first export only the year
        changes, saving a page load and a postback per year."""
        paths, form = [], None
        for year in years:
            dest = CACHE / f"{rtype}_{year}.csv"
            if not _fresh(dest, year):
                if form is None:
                    form = _Form(self.client, f"{BASE}/Campaign_Finance/CF_ContrCSV.aspx")
                    form.set("ddReportType", rtype, postback=True)
                form.set("ddReportYear", str(year), postback=True)
                resp = form.submit("btnExport", "Export to CSV")
                if "text/html" in resp.headers.get("content-type", ""):
                    raise RuntimeError(f"MEC export {rtype} {year} returned HTML, not CSV")
                _write(dest, resp.content)
            paths.append(dest)
            self.progress.tick()
        return paths

    def crosswalk(self, year: int) -> list[tuple[str, dict]]:
        """MECID <-> candidate name / office sought for each election in `year` (the 'Excel' export is an
        HTML table). Cached per year as JSON."""
        dest = CACHE / f"crosswalk_{year}.json"
        if not _fresh(dest, year):
            form = _Form(self.client, f"{BASE}/Campaign_Finance/CF12_SearchElection.aspx")
            if f'value="{year}"' not in form.page.text:
                log.info("mec.crosswalk_year_not_offered", year=year)
                self.progress.tick()
                return []
            form.set("ddElectionYear", str(year), postback=True)
            dates = re.findall(r'<option[^>]*value="(\d{1,2}/\d{1,2}/\d{4})"', form.page.text)
            if not dates:
                # Not cached: an empty answer would otherwise stick for 30 days.
                log.warning("mec.crosswalk_no_elections", year=year)
                self.progress.tick()
                return []
            records = []
            for election_date in dates:
                form.set("ddElectionDate", election_date, postback=True)
                form.submit("btnSearch", "Search")
                resp = form.submit("btnExport", "Excel Export")
                rows = re.findall(r"<tr[^>]*>(.*?)</tr>", resp.text, re.S)
                if "__VIEWSTATE" in resp.text[:200_000] or not rows:
                    # no candidates filed for this election: the search page comes back instead of a table
                    log.info("mec.crosswalk_empty", election_date=election_date)
                    continue
                for i, tr in enumerate(rows):
                    cells = [
                        html.unescape(re.sub(r"<[^>]+>", "", td)).strip()
                        for td in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S)
                    ]
                    if cells and cells[0] != "MECID":
                        records.append((f"{election_date}/{i}", {"election_date": election_date, "cells": cells}))
            _write(dest, json.dumps(records).encode())
        self.progress.tick()
        return [tuple(r) for r in json.loads(dest.read_bytes())]

    def lobbyist_expenditures(self) -> Path:
        dest = CACHE / "lobbyist_expenditures.csv"
        if not _fresh(dest, date.today().year):
            form = _Form(self.client, f"{BASE}/Lobbying/LobExpSearch.aspx")
            boxes = {
                k: "on"
                for k in (
                    "chkInd",
                    "chkGroup",
                    "chkSol",
                    "chkRep",
                    "chkSenator",
                    "chkSWO",
                    "chkELGO",
                    "chkJud",
                    "chkOther",
                )
            }
            criteria = {"txtDateFrom": LOBBYING_FROM, "txtDateTo": date.today().strftime("%m/%d/%Y"), **boxes}
            form.submit("btnSearch", "Search", criteria)
            resp = form.submit("btnExport", "Export to CSV", boxes)
            if "__VIEWSTATE" in resp.text[:200_000]:
                raise RuntimeError("MEC lobbyist expenditure export returned the search page, not CSV")
            _write(dest, resp.content)
        self.progress.tick()
        return dest


@loader("mec", service="www.mec.mo.gov", slow=True)
def load(shard: db.Shard) -> dict[str, int]:
    """Units: (report type, year) exports, crosswalk election years, and the lobbyist export."""
    if os.environ.get("MOGOV_MEC_OPT_IN") != "1":
        log.warning(
            "mec.skipped", reason="opt-in required (MOGOV_MEC_OPT_IN=1); see loaders/mec.py", fallback="TAP mirror"
        )
        return {}
    contrib_units = {rtype: [y for y in YEARS if shard.owns(f"{rtype}/{y}")] for rtype in REPORT_TYPES}
    crosswalk_years = [y for y in CROSSWALK_YEARS if shard.owns(f"crosswalk/{y}")]
    lobbying = shard.owns("lobbyist_expenditures")
    exports = _Exports()
    total = sum(map(len, contrib_units.values())) + len(crosswalk_years) + lobbying
    exports.progress = obs.Progress("MEC exports", total, log)
    # The quote/escape must be explicit: with non-strict sniffing DuckDB mis-read quoted names such as
    # "'Together With Schaper'" and silently merged the following rows (~2,800 rows lost across 2023-26).
    csv_opts = {
        "quote": '"',
        "escape": '"',
        "ignore_errors": True,
        "strict_mode": False,
        "normalize_names": True,
        "shard": shard,
    }
    counts = {}
    try:
        for rtype, years in contrib_units.items():
            table = f"mec_{rtype.lower()}"
            counts[table] = db.replace_csv(table, exports.contributions(rtype, years), **csv_opts)
        records = [r for year in crosswalk_years for r in exports.crosswalk(year)]
        counts["mec_candidate_committees"] = db.replace_json(
            "mec_candidate_committees",
            records,
            source_url=f"{BASE}/Campaign_Finance/CF12_SearchElection.aspx",
            shard=shard,
        )
        paths = [exports.lobbyist_expenditures()] if lobbying else []
        counts["mec_lobbyist_expenditures"] = db.replace_csv("mec_lobbyist_expenditures", paths, **csv_opts)
    finally:
        exports.close()
    exports.progress.finish()
    return counts
