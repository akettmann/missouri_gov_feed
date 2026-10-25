-- Which current state house, state senate and congressional districts reach each county, from the full
-- (unsimplified) TIGER boundaries, so "find my officials" can show a county view (#163). Also the cities whose
-- boundary covers the whole county (St. Louis city is both a county and a place), so their mayor counts as a
-- county-wide official.
--
-- Two boundaries that share an edge intersect along a line, and TIGER layers disagree by a few meters, so a
-- pair counts only when the overlap is real: more than min_overlap_km2 (0.1 km2, about 25 acres). That keeps
-- genuine small overlaps (Miller County / CD 4 is 0.78 km2) and drops edge noise. A city counts as covering the
-- county when its overlap is at least min_city_share (99%) of the county's area.
--
-- Areas come from the planar area of the lon/lat geometry scaled by cos(latitude): a few tenths of a percent
-- off at Missouri's latitudes, which does not matter against these thresholds.
{% set min_overlap_km2 = 0.1 %}
{% set min_city_share = 0.99 %}
{% set km2_per_sq_degree_at_equator = 111.32 * 110.57 %}

with counties as (
    select
        district_id,
        interior_lat,
        {{ mogov.geom_from_geojson('geometry_geojson') }} as geom
    from {{ ref('dim_district') }}
    where district_type = 'county'
),

sized_counties as (
    select
        *,
        {{ mogov.geom_area('geom') }} as sq_degrees
    from counties
),

areas as (
    select
        district_id,
        district_type,
        {{ mogov.geom_from_geojson('geometry_geojson') }} as geom
    from {{ ref('dim_district') }}
    where
        is_current
        and district_type in ('state_house', 'state_senate', 'us_house', 'place')
),

touching as (
    select
        c.district_id as county_id,
        c.interior_lat,
        c.sq_degrees as county_sq_degrees,
        c.geom as county_geom,
        a.district_id,
        a.district_type,
        a.geom as area_geom
    from sized_counties as c
    inner join areas as a on {{ mogov.geom_intersects('c.geom', 'a.geom') }}
),

pair_areas as (
    select
        county_id,
        district_id,
        district_type,
        interior_lat,
        county_sq_degrees,
        {{ mogov.geom_intersection_area('county_geom', 'area_geom') }} as overlap_sq_degrees
    from touching
),

sized as (
    select
        county_id,
        district_id,
        district_type,
        overlap_sq_degrees * cos(radians(interior_lat)) * {{ km2_per_sq_degree_at_equator }} as overlap_km2,
        overlap_sq_degrees / county_sq_degrees as share_of_county
    from pair_areas
)

select
    county_id,
    district_id,
    district_type,
    round(overlap_km2, 3) as overlap_km2,
    round(share_of_county, 4) as share_of_county
from sized
where
    overlap_km2 > {{ min_overlap_km2 }}
    and (district_type != 'place' or share_of_county >= {{ min_city_share }})
