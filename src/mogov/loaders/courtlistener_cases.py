"""Case history for officials who are or were judges or lawyers, from CourtListener (Free Law Project).

Stage 2: reads the people to look up from the dbt mart `marts.fct_legal_careers` (+ dim_official).
For each person it searches CourtListener's opinion index:
  judges   judge:"<surname>" in the courts they sit on (Missouri appellate + federal courts in Missouri)
  lawyers  attorney:"<first> <last>" across Missouri state and federal courts
Each hit lands as one raw row (case name, court, docket, date, judge/panel text, attorney text...).

Outcomes: with COURTLISTENER_TOKEN set (free account at courtlistener.com), each case's cluster is
fetched for its `disposition`, and the last ~1500 characters of the lead opinion are kept so dbt can
read "AFFIRMED"/"REVERSED"... from the decree. Without a token CourtListener allows ~5 requests/minute
and no cluster/opinion detail, so the loader runs search-only, capped by MOGOV_CL_MAX_QUERIES per run
(results are cached for 30 days, so repeated runs make progress).

Trial-court (circuit) cases are not in CourtListener; Missouri Case.net prohibits automated access.
"""

import json
import os
import time

import duckdb

from mogov import db, obs
from mogov.config import DB_PATH
from mogov.http import CacheMiss, RateLimited, fetch
from mogov.loaders import loader

log = obs.get_logger(__name__)

API = "https://www.courtlistener.com/api/rest/v4"
TOKEN = os.environ.get("COURTLISTENER_TOKEN", "").strip()
MO_STATE_COURTS = "mo moctapp moctapped moctappwd moctappsd"
MO_FEDERAL_COURTS = "moed mowd ca8"
JUDGE_COURTS = {
    "mo_supreme_court": "mo",
    "mo_court_of_appeals": "moctapp moctapped moctappwd moctappsd",
    "us_district_court": "moed mowd",
    "us_court_of_appeals": "ca8",
}
MAX_PAGES = int(os.environ.get("MOGOV_CL_MAX_PAGES", "5" if TOKEN else "1"))  # 20 results per page
MAX_QUERIES = int(os.environ.get("MOGOV_CL_MAX_QUERIES", "100000" if TOKEN else "60"))
MAX_DETAILS = int(os.environ.get("MOGOV_CL_MAX_DETAILS", "5000" if TOKEN else "0"))
PAUSE = float(os.environ.get("MOGOV_CL_PAUSE", "0.8" if TOKEN else "15"))  # <5,000/hour with token, 5/min without


def _headers() -> dict:
    return {"Authorization": f"Token {TOKEN}"} if TOKEN else {}


def _people() -> list[dict]:
    if not DB_PATH.exists():
        return []
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        try:
            rows = con.execute("""
                select o.official_id, o.full_name, o.given_name, o.family_name, o.office,
                       string_agg(distinct l.legal_role, ',') as roles
                from marts.fct_legal_careers l
                join marts.dim_official o using (official_id)
                group by all
            """).fetchall()
        except duckdb.CatalogException:
            return []
    cols = ["official_id", "full_name", "given_name", "family_name", "office", "roles"]
    return [dict(zip(cols, r, strict=True)) for r in rows]


def _queries(person: dict) -> list[tuple[str, str, str]]:
    """(role, query, courts) searches for one person."""
    out = []
    family = (person["family_name"] or "").strip()
    given = (person["given_name"] or "").split(" ")[0].strip()
    if not family:
        return out
    if person["office"] in JUDGE_COURTS:
        out.append(("judge", f'judge:"{family}"', JUDGE_COURTS[person["office"]]))
    roles = person["roles"] or ""
    # lawyers, and judges whose cases CourtListener doesn't index (trial courts): search their law practice
    if "lawyer" in roles or person["office"] not in JUDGE_COURTS:
        out.append(("attorney", f'attorney:"{given} {family}"', f"{MO_STATE_COURTS} {MO_FEDERAL_COURTS}"))
    return out


def _search(query: str, courts: str, *, cache_only: bool = False) -> list[dict]:
    """Up to MAX_PAGES pages of hits. If the quota runs out mid-pagination, the pages already fetched are
    returned and RateLimited is re-raised on the next call by the caller's quota flag."""
    results, url, params = (
        [],
        f"{API}/search/",
        {"type": "o", "q": query, "court": courts, "order_by": "dateFiled desc"},
    )
    for _ in range(MAX_PAGES):
        try:
            raw = fetch(
                url,
                params,
                headers=_headers(),
                max_age=30 * 86400,
                delay=0 if cache_only else PAUSE,
                cache_only=cache_only,
            )
        except CacheMiss:
            break
        body = json.loads(raw)
        results.extend(body.get("results", []))
        url, params = body.get("next"), None
        if not url:
            break
    return results


def _details(cluster_id: int, *, cache_only: bool = False) -> dict:
    cluster = json.loads(
        fetch(
            f"{API}/clusters/{cluster_id}/",
            {"fields": "disposition,sub_opinions,syllabus"},
            headers=_headers(),
            max_age=None,
            cache_only=cache_only,
            delay=PAUSE,
        )
    )
    tail = None
    if cluster.get("sub_opinions"):
        op = json.loads(
            fetch(
                cluster["sub_opinions"][0],
                {"fields": "plain_text"},
                headers=_headers(),
                max_age=None,
                delay=PAUSE,
                cache_only=cache_only,
            )
        )
        text = (op.get("plain_text") or "").strip()
        tail = text[-1500:] if text else None
    return {"disposition": cluster.get("disposition"), "opinion_tail": tail}


@loader("courtlistener_cases", stage=2)
def load() -> dict[str, int]:
    people = _people()
    if not people:
        log.warning("cases.skipped", reason="no legal-career officials yet; run `mogov build` first")
        return {"cl_cases": db.replace_json("cl_cases", [], source_url=API)}
    if not TOKEN:
        log.warning("cases.no_token", max_queries=MAX_QUERIES, effect="search only, no outcomes")
    rows, n_queries, n_details, started = [], 0, 0, time.time()
    # Once CourtListener's quota runs out (e.g. 125 searches/day on some tokens), keep going from cache only:
    # everything already fetched still lands, and the next run resumes where this one stopped.
    quota_hit: RateLimited | None = None
    for person in people:
        for role, query, courts in _queries(person):
            if n_queries >= MAX_QUERIES:
                break
            n_queries += 1
            try:
                hits = _search(query, courts, cache_only=quota_hit is not None)
            except RateLimited as exc:
                quota_hit = exc
                log.warning(
                    "cases.quota_exhausted", retry_after_s=round(exc.retry_after), effect="continuing from cache"
                )
                hits = _search(query, courts, cache_only=True)
            except Exception as exc:
                log.warning("cases.search_failed", query=query, error=str(exc))
                continue
            for hit in hits:
                rec = {
                    "official_id": person["official_id"],
                    "role_searched": role,
                    "query": query,
                    **{
                        k: hit.get(k)
                        for k in (
                            "cluster_id",
                            "caseName",
                            "court_id",
                            "court",
                            "docketNumber",
                            "dateFiled",
                            "judge",
                            "attorney",
                            "panel_names",
                            "status",
                            "citation",
                            "absolute_url",
                            "posture",
                            "procedural_history",
                        )
                    },
                }
                if TOKEN and n_details < MAX_DETAILS and hit.get("cluster_id"):
                    try:
                        rec.update(_details(hit["cluster_id"], cache_only=quota_hit is not None))
                        n_details += 1
                    except RateLimited as exc:
                        quota_hit = exc
                    except CacheMiss:
                        pass
                    except Exception as exc:
                        rec["detail_error"] = str(exc)
                rows.append((f"{person['official_id']}/{role}/{hit.get('cluster_id')}", rec))
    log.info(
        "cases.done",
        searches=n_queries,
        details=n_details,
        seconds=round(time.time() - started),
        quota_exhausted=quota_hit is not None,
        resume_after_s=round(quota_hit.retry_after) if quota_hit else None,
    )
    return {"cl_cases": db.replace_json("cl_cases", rows, source_url=API)}
