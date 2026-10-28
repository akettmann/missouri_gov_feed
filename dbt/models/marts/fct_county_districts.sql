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
-- Area alone is not enough: where two TIGER vintages (CD119 vs the 2026 layers) disagree along a county line,
-- the overlap is a long thin strip (e.g. Pulaski County / CD 3, about 72 m x 6 km = 0.36 km2) that passes the
-- area threshold but is not a real overlap. So a pair must also survive an inward buffer of core_buffer_m
-- (120 m) applied to the overlap polygon: the overlap must contain a circle of at least 120 m radius, which
-- any real overlap does and a sliver does not. Verified against exact shapely geometry in
-- scripts/check_county_districts.py. The buffer is in degrees, converted from metres with the longitude degree
-- length (111,320 m * cos(latitude)), so it erodes 120 m east-west and about 152 m north-south at Missouri's
-- latitudes: at least 120 m in every direction. Any kept overlap is therefore more than 240 m wide in every
-- direction (real overlaps here are at least about 1.7 km wide), while the thin slivers seen (about 72 m
-- wide) go.
--
-- Areas come from the planar area of the lon/lat geometry scaled by cos(latitude): a few tenths of a percent
-- off at Missouri's latitudes, which does not matter against these thresholds.
{% set min_overlap_km2 = 0.1 %}
{% set min_city_share = 0.99 %}
{% set core_buffer_m = 120 %}
{% set km2_per_sq_degree_at_equator = 111.32 * 110.57 %}

with counties as (
    select
        district_id,
        interior_lat,
        {{ mogov.geom_from_geojson('geometry_geojson') }} as geom
    from {{ ref('dim_district') }}
    where
        is_current
        and district_type = 'county'
),

sized_counties as (
    select
        *,
        {{ mogov.geom_area('geom') }} as sq_degrees
    from counties
),

parsed_areas as (
    select
        district_id,
        district_type,
        {{ mogov.geom_from_geojson('geometry_geojson') }} as geom
    from {{ ref('dim_district') }}
    where
        is_current
        and district_type in ('state_house', 'state_senate', 'us_house', 'place')
),

areas as (
    select
        *,
        {{ mogov.geom_area('geom') }} as sq_degrees
    from parsed_areas
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
    -- a place smaller than the city-share cutoff (with slack for rounding) can never cover the county, so skip
    -- its costly intersection
    where a.district_type != 'place' or a.sq_degrees >= c.sq_degrees * {{ min_city_share - 0.01 }}
),

pair_overlaps as (
    -- each pair's intersection is computed once; the area and the inward buffer both read it
    select
        county_id,
        district_id,
        district_type,
        interior_lat,
        county_sq_degrees,
        {{ mogov.geom_intersection('county_geom', 'area_geom') }} as overlap_geom
    from touching
),

sized as (
    select
        county_id,
        district_id,
        district_type,
        interior_lat,
        overlap_geom,
        {{ mogov.geom_area('overlap_geom') }} * cos(radians(interior_lat)) * {{ km2_per_sq_degree_at_equator }}
            as overlap_km2,
        {{ mogov.geom_area('overlap_geom') }} / county_sq_degrees as share_of_county
    from pair_overlaps
),

-- only pairs that pass the cheap area and city-share tests pay for the buffer
candidates as (
    select *
    from sized
    where
        overlap_km2 > {{ min_overlap_km2 }}
        and (district_type != 'place' or share_of_county >= {{ min_city_share }})
),

cores as (
    select
        county_id,
        district_id,
        district_type,
        overlap_km2,
        share_of_county,
        {{ mogov.geom_area(mogov.geom_buffer(
            'overlap_geom',
            '-' ~ mogov.geom_metres_to_degrees(core_buffer_m, 'interior_lat')
        )) }} as core_sq_degrees
    from candidates
)

select
    county_id,
    district_id,
    district_type,
    round(overlap_km2, 3) as overlap_km2,
    round(share_of_county, 4) as share_of_county
from cores
where core_sq_degrees > 0
