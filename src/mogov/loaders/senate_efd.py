"""U.S. Senate electronic financial disclosures (efdsearch.senate.gov) for Missouri senators/candidates:
annual reports (assets, income, liabilities, positions, agreements, gifts, travel) and periodic
transaction reports (stock trades).

OPT-IN: the site requires accepting a statement that the data won't be used for unlawful or
commercial purposes, credit rating, or solicitation (5 U.S.C. app. 105(c)). Running this loader
accepts that statement on your behalf, so it only runs with MOGOV_ACCEPT_SENATE_EFD_TERMS=1.

Web-filed reports are HTML tables; every table row lands as one raw record (section, headers, cells)
and dbt reshapes them. Paper filings are page images: recorded with is_paper = true, not parsed.
"""

import os
import re
import time

import httpx
from bs4 import BeautifulSoup

from mogov import db
from mogov.config import USER_AGENT
from mogov.loaders import loader

BASE = "https://efdsearch.senate.gov"
FIRST_DATE = os.environ.get("MOGOV_SENATE_EFD_FROM", "01/01/2012 00:00:00")


def _session() -> httpx.Client:
    s = httpx.Client(headers={"User-Agent": USER_AGENT}, follow_redirects=True, timeout=60)
    home = s.get(f"{BASE}/search/home/")
    token = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', home.text).group(1)
    s.post(
        f"{BASE}/search/home/",
        data={"prohibition_agreement": "1", "csrfmiddlewaretoken": token},
        headers={"Referer": f"{BASE}/search/home/"},
    )
    return s


def _search(s: httpx.Client) -> list[list[str]]:
    rows, start = [], 0
    while True:
        csrf = s.cookies.get("csrftoken")
        resp = s.post(
            f"{BASE}/search/report/data/",
            headers={"X-CSRFToken": csrf, "Referer": f"{BASE}/search/"},
            data={
                "start": start,
                "length": 100,
                "report_types": "[]",
                "filer_types": "[]",
                "submitted_start_date": FIRST_DATE,
                "submitted_end_date": "",
                "candidate_state": "MO",
                "senator_state": "MO",
                "office_id": "",
                "first_name": "",
                "last_name": "",
                "csrfmiddlewaretoken": csrf,
            },
        )
        resp.raise_for_status()
        body = resp.json()
        rows.extend(body["data"])
        start += 100
        if start >= body["recordsFiltered"]:
            return rows


def _report_tables(html: str) -> list[dict]:
    soup = BeautifulSoup(html, "lxml")
    out = []
    for t_idx, table in enumerate(soup.find_all("table")):
        heading = table.find_previous(["h3", "h4", "h2"])
        headers = [th.get_text(" ", strip=True) for th in table.find_all("th")]
        for r_idx, tr in enumerate(table.find_all("tr")):
            cells = [td.get_text(" ", strip=True) for td in tr.find_all("td")]
            if cells:
                out.append(
                    {
                        "section": heading.get_text(" ", strip=True) if heading else None,
                        "table_index": t_idx,
                        "row_index": r_idx,
                        "headers": headers,
                        "cells": cells,
                    }
                )
    return out


@loader("senate_efd")
def load() -> dict[str, int]:
    if os.environ.get("MOGOV_ACCEPT_SENATE_EFD_TERMS") != "1":
        print("[senate_efd] opt-in required: set MOGOV_ACCEPT_SENATE_EFD_TERMS=1 to accept the eFD use statement")
        return {}
    s = _session()
    filings, rows = [], []
    for first, last, filer, link_html, submitted in _search(s):
        href = re.search(r'href="([^"]+)"', link_html).group(1)
        title = re.sub(r"<[^>]+>", "", link_html).strip()
        rec = {
            "first_name": first,
            "last_name": last,
            "filer_type": filer,
            "title": title,
            "submitted": submitted,
            "url": BASE + href,
            "is_paper": "/paper/" in href,
        }
        filings.append((href, rec))
        if rec["is_paper"]:
            continue
        time.sleep(1.0)
        page = s.get(BASE + href)
        for i, r in enumerate(_report_tables(page.text)):
            rows.append(
                (
                    f"{href}#{i}",
                    {
                        "url": BASE + href,
                        "first_name": first,
                        "last_name": last,
                        "title": title,
                        "submitted": submitted,
                        **r,
                    },
                )
            )
    return {
        "senate_efd_filings": db.replace_json("senate_efd_filings", filings, source_url=BASE),
        "senate_efd_rows": db.replace_json("senate_efd_rows", rows, source_url=BASE),
    }
