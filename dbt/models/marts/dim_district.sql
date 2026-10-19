-- Areas Missouri officials are elected or appointed for, with their boundaries (Census TIGER/Line, GeoJSON)
-- for "find my officials" lookups: state senate and house districts, congressional districts (every loaded
-- Congress; is_current marks the Congress in session), counties (with their judicial circuit) and places
-- (cities, for mayors).
with features as (
    select
        *,
        case layer
            when 'sldu' then 'state_senate'
            when 'sldl' then 'state_house'
            when 'cd' then 'us_house'
            else layer
        end as district_type
    from {{ ref('stg_census_tiger__features') }}
),

circuits as (
    select
        county_key,
        circuit_number
    from {{ ref('int_bluebook__county_circuits') }}
)

select
    case
        when f.district_type = 'us_house'
            then
                'us_house:' || {{ dbt.safe_cast('f.congress', dbt.type_string()) }} || ':'
                || {{ dbt.safe_cast('f.district_number', dbt.type_string()) }}
        when f.district_type in ('state_senate', 'state_house')
            then f.district_type || ':' || {{ dbt.safe_cast('f.district_number', dbt.type_string()) }}
        else f.district_type || ':' || f.geoid
    end as district_id,
    f.district_type,
    f.district_number,
    f.congress,
    -- the Congress in session: the 1st began in 1789 and each lasts two years (off by one on Jan 1-2 of odd years)
    coalesce(
        f.congress = cast(floor((extract(year from current_date) - 1789) / 2) as {{ dbt.type_int() }}) + 1,
        true
    ) as is_current,
    f.name,
    f.name_with_type,
    f.geoid,
    c.circuit_number as judicial_circuit,
    f.land_area_m2,
    f.interior_lat,
    f.interior_lon,
    f.vintage,
    f.geometry_geojson,
    f.source_url
from features as f
left join circuits as c
    on
        f.district_type = 'county'
        and {{ mogov.regex_replace_all(mogov.name_key('f.name_with_type'), ' county$', '') }} = c.county_key
