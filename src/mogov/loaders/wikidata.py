"""Wikidata facts for officials: positions held (past offices), occupations (lawyer/judge/prosecutor...),
employers, and relatives -- plus any organizations those relatives lead (CEO, director/manager, board
member, chairperson, founder, owner) for the "family members in company leadership" view.

People are identified by Wikidata QID, taken from the landed Open States roster and
congress-legislators files (run those loaders first). Officials without a QID are matched in dbt
by name against the label search below, so coverage is best for well-documented officials.
"""

import json

import duckdb

from mogov import db
from mogov.config import CONTACT
from mogov.http import post
from mogov.loaders import loader

ENDPOINT = "https://query.wikidata.org/sparql"
BATCH = 40

POSITIONS = """
SELECT ?person ?position ?positionLabel ?start ?end ?districtLabel WHERE {
  VALUES ?person { %s }
  ?person p:P39 ?st . ?st ps:P39 ?position .
  OPTIONAL { ?st pq:P580 ?start } OPTIONAL { ?st pq:P582 ?end } OPTIONAL { ?st pq:P768 ?district }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

# occupation, employer, political party, educated at, member of
ATTRIBUTES = """
SELECT ?person ?prop ?value ?valueLabel WHERE {
  VALUES ?person { %s }
  VALUES ?prop { wdt:P106 wdt:P108 wdt:P102 wdt:P69 wdt:P463 }
  ?person ?prop ?value .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

# father, mother, spouse, child, sibling, relative, partner -> organizations they lead
# (CEO, director/manager, board member, chairperson, founded by, owned by) and offices they hold.
RELATIVES = """
SELECT ?person ?relation ?relative ?relativeLabel ?role ?org ?orgLabel ?position ?positionLabel WHERE {
  VALUES ?person { %s }
  VALUES ?relation { wdt:P22 wdt:P25 wdt:P26 wdt:P40 wdt:P3373 wdt:P1038 wdt:P451 }
  ?person ?relation ?relative .
  OPTIONAL {
    VALUES ?role { wdt:P169 wdt:P1037 wdt:P3320 wdt:P488 wdt:P112 wdt:P127 }
    ?org ?role ?relative .
  }
  OPTIONAL { ?relative wdt:P39 ?position . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

# organizations the official themself leads / founded / owns
OWN_LEADERSHIP = """
SELECT ?person ?role ?org ?orgLabel WHERE {
  VALUES ?person { %s }
  VALUES ?role { wdt:P169 wdt:P1037 wdt:P3320 wdt:P488 wdt:P112 wdt:P127 }
  ?org ?role ?person .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

# Living people who held any position whose jurisdiction (P1001) is Missouri (Q1581), or a seat in a
# Missouri court / legislature body (P361 part of). Gives QIDs for officials the rosters don't link.
DISCOVER = """
SELECT DISTINCT ?person ?personLabel ?position ?positionLabel WHERE {
  { ?position wdt:P1001 wd:Q1581 . } UNION { ?position wdt:P361/wdt:P1001 wd:Q1581 . }
  ?person wdt:P39 ?position ; wdt:P31 wd:Q5 .
  FILTER NOT EXISTS { ?person wdt:P570 ?died }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

TEMPLATES = {
    "wikidata_positions": POSITIONS,
    "wikidata_attributes": ATTRIBUTES,
    "wikidata_relatives": RELATIVES,
    "wikidata_own_leadership": OWN_LEADERSHIP,
}


def _qids() -> list[str]:
    with duckdb.connect() as con:
        rows = con.execute(f"""
            select distinct wikidata from read_parquet('{db.raw_path("openstates_current_csv").as_posix()}')
            where wikidata like 'Q%'
            union
            select distinct json_extract_string(payload, '$.id.wikidata')
            from read_parquet('{db.raw_path("congress_legislators_current").as_posix()}')
            where json_extract_string(payload, '$.id.wikidata') like 'Q%'
        """).fetchall()
    return sorted(r[0] for r in rows if r[0])


def _sparql(query: str) -> list[dict]:
    body = post(
        ENDPOINT,
        data={"query": query, "format": "json"},
        headers={"Accept": "application/sparql-results+json"},
        max_age=7 * 86400,
        delay=1.0,
    )
    bindings = json.loads(body)["results"]["bindings"]
    return [{k: v["value"] for k, v in b.items()} for b in bindings]


@loader("wikidata")
def load() -> dict[str, int]:
    if not CONTACT:
        # https://meta.wikimedia.org/wiki/User-Agent_policy -- requests without contact info are refused.
        print("[wikidata] MOGOV_CONTACT not set (Wikimedia requires contact info in the User-Agent); skipping")
        return {t: db.replace_json(t, [], source_url=ENDPOINT) for t in [*TEMPLATES, "wikidata_mo_officeholders"]}
    discovered = _sparql(DISCOVER)
    qids = sorted(set(_qids()) | {r["person"].rsplit("/", 1)[-1] for r in discovered})
    out: dict[str, list] = {table: [] for table in TEMPLATES}
    out["wikidata_mo_officeholders"] = [(str(i), r) for i, r in enumerate(discovered)]
    for i in range(0, len(qids), BATCH):
        values = " ".join(f"wd:{q}" for q in qids[i : i + BATCH])
        for table, template in TEMPLATES.items():
            for j, row in enumerate(_sparql(template % values)):
                out[table].append((f"{i}/{j}", row))
    return {table: db.replace_json(table, rows, source_url=ENDPOINT) for table, rows in out.items()}
