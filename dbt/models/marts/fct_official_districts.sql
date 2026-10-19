-- Which areas (dim_district) each official serves:
--   elected from      state senators and representatives (district number), U.S. representatives (district
--                     of the Congress in session)
--   judicial circuit  circuit and associate circuit judges: every county of their circuit
--   mayor of          mayors: the place whose name matches their title ("Mayor Of Saint Louis" -> St. Louis)
-- Statewide offices (executives, U.S. senators, Supreme Court) serve every area and have no rows. Courts of
-- appeals and federal district courts are not mapped yet.
with officials as (
    select
        official_id,
        office,
        {{ dbt.safe_cast('district', dbt.type_int()) }} as district_number,
        {{ mogov.regex_replace_all(
            mogov.regex_replace_all(mogov.name_key('office_title'), '^mayor of ', ''), '^saint ', 'st '
        ) }} as mayor_place_key
    from {{ ref('dim_official') }}
),

districts as (
    select
        *,
        {{ mogov.regex_replace_all(mogov.name_key('name'), '^saint ', 'st ') }} as place_key
    from {{ ref('dim_district') }}
)

select
    o.official_id,
    d.district_id,
    o.office,
    'elected from' as relation
from officials as o
inner join districts as d
    on
        o.office = d.district_type
        and o.district_number = d.district_number
        and d.is_current
where o.office in ('state_senate', 'state_house', 'us_house')

union all

select
    o.official_id,
    d.district_id,
    o.office,
    'judicial circuit' as relation
from officials as o
inner join districts as d
    on
        d.district_type = 'county'
        and o.district_number = d.judicial_circuit
where o.office in ('mo_circuit_judge', 'mo_associate_circuit_judge')

union all

select
    o.official_id,
    d.district_id,
    o.office,
    'mayor of' as relation
from officials as o
inner join districts as d
    on
        d.district_type = 'place'
        and o.mayor_place_key = d.place_key
where o.office = 'mayor'
