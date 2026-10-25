"""Compare marts.fct_county_districts with exact shapely intersections of the unsimplified TIGER boundaries.

    uv run --with shapely python scripts/check_county_districts.py [path/to/mogov.duckdb]

Reads dim_district read-only, intersects every current county with every current state house, state senate and
congressional district, and reports, against the model's threshold (overlap > 0.1 km2): false positives (in the
model, not in the exact result), misses (the reverse) and how many counties span more than one House district.
Exits 1 on any disagreement. Needs dbt to have built dim_district and fct_county_districts.
"""

import json
import math
import sys

import duckdb
from shapely import STRtree
from shapely.geometry import shape

MIN_KM2 = 0.1
TYPES = ("state_house", "state_senate", "us_house")


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "data/mogov.duckdb"
    con = duckdb.connect(path, read_only=True)
    rows = con.execute(
        "select district_id, district_type, interior_lat, geometry_geojson from marts.dim_district "
        "where district_type = 'county' or (is_current and district_type in ('state_house','state_senate','us_house'))"
    ).fetchall()
    counties = {i: (shape(json.loads(g)), lat) for i, t, lat, g in rows if t == "county"}
    areas = {i: (t, shape(json.loads(g))) for i, t, _, g in rows if t != "county"}
    ids = list(areas)
    tree = STRtree([areas[i][1] for i in ids])

    exact: dict[tuple[str, str], float] = {}
    for cid, (cg, lat) in counties.items():
        for k in tree.query(cg, predicate="intersects"):
            did = ids[k]
            km2 = cg.intersection(areas[did][1]).area * math.cos(math.radians(lat)) * 111.32 * 110.57
            exact[cid, did] = km2
    wanted = {k for k, v in exact.items() if v > MIN_KM2}
    model = {
        (c, d)
        for c, d in con.execute(
            "select county_id, district_id from marts.fct_county_districts where district_type != 'place'"
        ).fetchall()
    }
    touching_zero = sum(1 for v in exact.values() if v <= 1e-9)
    false_pos = sorted(model - wanted)
    missed = sorted(wanted - model)
    print(f"counties={len(counties)} districts={len(areas)}")
    print(f"exact pairs that intersect (any area): {len(exact)}, of which touch with ~0 area: {touching_zero}")
    print(f"exact pairs with overlap > {MIN_KM2} km2: {len(wanted)}; model pairs: {len(model)}")
    print(f"false positives (model, not exact): {len(false_pos)} {false_pos[:5]}")
    print(f"misses (exact, not model): {len(missed)} {missed[:5]}")
    for label, minimum in (("any positive area", 1e-9), (f"> {MIN_KM2} km2", MIN_KM2)):
        per = {}
        for (c, d), v in exact.items():
            if areas[d][0] == "state_house" and v > minimum:
                per[c] = per.get(c, 0) + 1
        print(f"counties spanning >1 House district ({label}): {sum(1 for n in per.values() if n > 1)}")
    return 1 if false_pos or missed else 0


if __name__ == "__main__":
    sys.exit(main())
