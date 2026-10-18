"""Missouri Ethics Commission (www.mec.mo.gov): current campaign finance, candidate<->committee crosswalk,
and lobbyist expenditures (gifts) to public officials. Fills in what the TAP mirror lacks after 2022.

OPT-IN (MOGOV_MEC_OPT_IN=1). Read before enabling:
  * MEC's robots.txt disallows crawlers on these export pages (CF_ContrCSV.aspx, Lob_ExpCSV.aspx...).
    They're public tools for downloading public records, but automated use is against the site's stated
    crawler policy. Consider asking MEC (helpdesk@mec.mo.gov) first.
  * The site sits behind Imperva/Incapsula, which rejects non-browser User-Agents. This loader sends the
    pipeline's honest User-Agent unless you set MOGOV_MEC_USER_AGENT yourself.
Requests are serial with multi-second pauses; exports are cached for a week.

Personal financial disclosure statements (PFDs) are NOT online: MEC releases them only on written
Sunshine Law (RSMo 610) request, so they're not loaded here.
"""

import html
import os
import re
import time
from datetime import date

import httpx

from mogov import db
from mogov.config import CACHE_DIR, USER_AGENT
from mogov.loaders import loader

BASE = "https://www.mec.mo.gov/MEC"
P = "ctl00$ctl00$ContentPlaceHolder$ContentPlaceHolder1$"
YEARS = [int(y) for y in os.environ.get("MOGOV_MEC_YEARS", "2023,2024,2025,2026").split(",")]
# report types: itemized contributions received, contributions made, itemized expenditures, report summaries
# Elections whose candidate<->committee lists to pull. Wider than YEARS: officials elected years ago still
# raise money through the committee they registered then.
CROSSWALK_YEARS = [
    int(y) for y in os.environ.get("MOGOV_MEC_CROSSWALK_YEARS", "2016,2018,2020,2022,2024,2026").split(",")
]
REPORT_TYPES = os.environ.get("MOGOV_MEC_REPORT_TYPES", "CD1_A,CD3_C,CD3_B,summary").split(",")
PAUSE = 3.0


class _Form:
    def __init__(self, client: httpx.Client, url: str):
        self.client, self.url = client, url
        self.page = self._send(None)

    def _send(self, data: dict | None) -> httpx.Response:
        time.sleep(PAUSE)
        if data is None:
            resp = self.client.get(self.url)
        else:
            resp = self.client.post(self.url, data=data, headers={"Referer": self.url})
        resp.raise_for_status()
        if "Incapsula" in resp.text[:2000]:
            raise RuntimeError(f"MEC bot protection rejected the request for {self.url}")
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
            self.page = self._send(f)

    def submit(self, button: str, label: str, extra: dict | None = None) -> httpx.Response:
        f = self.fields()
        f.update({P + k: v for k, v in (extra or {}).items()})
        f["__EVENTTARGET"] = ""
        f[P + button] = label
        resp = self._send(f)
        self.page = resp
        return resp


def _client() -> httpx.Client:
    ua = os.environ.get("MOGOV_MEC_USER_AGENT", USER_AGENT)
    return httpx.Client(headers={"User-Agent": ua}, follow_redirects=True, timeout=httpx.Timeout(600, connect=30))


def _contributions(client: httpx.Client) -> dict[str, int]:
    counts = {}
    for rtype in REPORT_TYPES:
        paths = []
        for year in YEARS:
            dest = CACHE_DIR / "mec" / f"{rtype}_{year}.csv"
            fresh = dest.exists() and (year < date.today().year or time.time() - dest.stat().st_mtime < 7 * 86400)
            if not fresh:
                form = _Form(client, f"{BASE}/Campaign_Finance/CF_ContrCSV.aspx")
                form.set("ddReportType", rtype, postback=True)
                form.set("ddReportYear", str(year), postback=True)
                resp = form.submit("btnExport", "Export to CSV")
                if "text/html" in resp.headers.get("content-type", ""):
                    raise RuntimeError(f"MEC export {rtype} {year} returned HTML, not CSV")
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(resp.content)
            paths.append(dest)
        counts[f"mec_{rtype.lower()}"] = db.replace_csv(
            f"mec_{rtype.lower()}", paths, ignore_errors=True, strict_mode=False, normalize_names=True
        )
    return counts


def _candidate_crosswalk(client: httpx.Client) -> int:
    """MECID <-> candidate name / office sought, per election date (the 'Excel' export is an HTML table)."""
    records = []
    for year in CROSSWALK_YEARS:
        form = _Form(client, f"{BASE}/Campaign_Finance/CF12_SearchElection.aspx")
        form.set("ddElectionYear", str(year), postback=True)
        dates = re.findall(r'<option[^>]*value="(\d{1,2}/\d{1,2}/\d{4})"', form.page.text)
        for election_date in dates:
            form.set("ddElectionDate", election_date, postback=True)
            form.submit("btnSearch", "Search")
            resp = form.submit("btnExport", "Excel Export")
            for i, tr in enumerate(re.findall(r"<tr[^>]*>(.*?)</tr>", resp.text, re.S)):
                cells = [
                    html.unescape(re.sub(r"<[^>]+>", "", td)).strip()
                    for td in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S)
                ]
                if cells and cells[0] != "MECID":
                    records.append((f"{election_date}/{i}", {"election_date": election_date, "cells": cells}))
    return db.replace_json(
        "mec_candidate_committees", records, source_url=f"{BASE}/Campaign_Finance/CF12_SearchElection.aspx"
    )


def _lobbyist_expenditures(client: httpx.Client) -> int:
    form = _Form(client, f"{BASE}/Lobbying/LobExpSearch.aspx")
    boxes = {
        k: "on"
        for k in ("chkInd", "chkGroup", "chkSol", "chkRep", "chkSenator", "chkSWO", "chkELGO", "chkJud", "chkOther")
    }
    form.submit(
        "btnSearch", "Search", {"txtDateFrom": "01/01/2019", "txtDateTo": date.today().strftime("%m/%d/%Y"), **boxes}
    )
    resp = form.submit("btnExport", "Export to CSV", boxes)
    dest = CACHE_DIR / "mec" / "lobbyist_expenditures.csv"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(resp.content)
    return db.replace_csv(
        "mec_lobbyist_expenditures", dest, ignore_errors=True, strict_mode=False, normalize_names=True
    )


@loader("mec")
def load() -> dict[str, int]:
    if os.environ.get("MOGOV_MEC_OPT_IN") != "1":
        print(
            "[mec] opt-in required (MOGOV_MEC_OPT_IN=1); see src/mogov/loaders/mec.py for why. Using TAP mirror only."
        )
        return {}
    with _client() as client:
        counts = _contributions(client)
        counts["mec_candidate_committees"] = _candidate_crosswalk(client)
        counts["mec_lobbyist_expenditures"] = _lobbyist_expenditures(client)
    return counts
