"""American Conservative Union (CPAC) legislative ratings for Missouri legislators.

Uses the GraphQL API behind ratings.conservative.org (undocumented, no auth, http only), one query
for all MO people with their yearly ratings and chamber/district history. One interest group's
scorecard: an indicator of alignment with that group, not a neutral measure.
"""

import json

from mogov import db
from mogov.http import post
from mogov.loaders import loader

URL = "http://production.data.conservative.org/v1/graphql"
QUERY = """
query MoRatings {
  ratings_people(where: {state: {_eq: "MO"}}) {
    id firstName lastName
    acuRatings { rating year }
    history { chamber party district year }
  }
}
"""


@loader("acu_ratings")
def load(shard: db.Shard) -> dict[str, int]:
    """One unit: the single GraphQL query."""
    if not shard.owns("acu_ratings"):
        return {"acu_ratings": db.replace_json("acu_ratings", [], source_url=URL, shard=shard)}
    body = json.loads(post(URL, json_body={"query": QUERY}, max_age=30 * 86400))
    if "errors" in body:
        raise RuntimeError(f"ACU GraphQL error: {body['errors']}")
    people = body["data"]["ratings_people"]
    return {
        "acu_ratings": db.replace_json("acu_ratings", ((str(p["id"]), p) for p in people), source_url=URL, shard=shard)
    }
