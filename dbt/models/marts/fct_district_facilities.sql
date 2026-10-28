-- EPA-regulated facilities (EPA FRS) inside each current area of dim_district: state house and senate
-- districts, the U.S. House districts of the Congress in session, counties and places. A facility sits in one
-- area of each type, found by its coordinates; the few whose coordinates fall outside Missouri have no rows.
-- Speed: the exact point-in-polygon test against polygons of up to 300k vertices dominated the build, so each
-- area is first clipped to the grid cells that hold facilities and a facility is tested only against the small
-- piece of its own cell. The result equals the full-polygon test:
--  * the coordinates are 32-bit floats; the cell index is computed in double precision (in 32-bit the 1e-6
--    margin is below the spacing of floats near 95 and facilities on cell edges were lost);
--  * cell size 0.125 degrees is a power of two, so floor(coordinate / 0.125) is exact in floating point
--    (0.1 is not, and loses rows); each facility is in exactly one cell, so no row is duplicated;
--  * the clip window is the cell grown by 1e-6 degrees on every side, so a facility on a cell edge is strictly
--    inside its window; inside the window, point-in-(area clipped to window) = point-in-area, including
--    facilities on the area's own boundary (outside for both, as st_contains excludes the boundary).
with areas as (
    select
        district_id,
        {{ mogov.geom_from_geojson('geometry_geojson') }} as geom
    from {{ ref('dim_district') }}
    where
        is_current
        and district_type in ('state_house', 'state_senate', 'us_house', 'county', 'place')
),

facilities as (
    select
        *,
        {{ mogov.geom_point('longitude', 'latitude') }} as geom,
        floor(cast(longitude as double precision) / 0.125) as cell_x,
        floor(cast(latitude as double precision) / 0.125) as cell_y
    from {{ ref('int_epa_frs__facilities') }}
),

cell_ids as (
    select distinct
        cell_x,
        cell_y
    from facilities
    where longitude is not null and latitude is not null
),

cells as (
    select
        cell_x,
        cell_y,
        {{ mogov.geom_envelope('cell_x * 0.125 - 0.000001', 'cell_y * 0.125 - 0.000001',
                               '(cell_x + 1) * 0.125 + 0.000001', '(cell_y + 1) * 0.125 + 0.000001') }}
            as window_geom
    from cell_ids
),

pieces as (
    select
        a.district_id,
        c.cell_x,
        c.cell_y,
        {{ mogov.geom_intersection('a.geom', 'c.window_geom') }} as geom
    from areas as a
    inner join cells as c on {{ mogov.geom_intersects('a.geom', 'c.window_geom') }}
)

select
    a.district_id,
    f.registry_id,
    f.facility_name,
    f.address,
    f.city,
    f.postal_code,
    f.owner_name,
    f.owner_type,
    f.parent_company_name,
    f.naics_code,
    f.naics_description,
    f.is_government,
    f.latitude,
    f.longitude,
    f.frs_url
from facilities as f
inner join pieces
    as a on f.cell_x = a.cell_x and f.cell_y = a.cell_y
and {{ mogov.geom_contains('a.geom', 'f.geom') }}
