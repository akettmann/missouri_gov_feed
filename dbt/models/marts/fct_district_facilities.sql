-- EPA-regulated facilities (EPA FRS) inside each current area of dim_district: state house and senate
-- districts, the U.S. House districts of the Congress in session, counties and places. A facility sits in one
-- area of each type, found by its coordinates; the few whose coordinates fall outside Missouri have no rows.
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
        {{ mogov.geom_point('longitude', 'latitude') }} as geom
    from {{ ref('int_epa_frs__facilities') }}
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
inner join areas as a on {{ mogov.geom_contains('a.geom', 'f.geom') }}
