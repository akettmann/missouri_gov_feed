-- Which areas (dim_district) each official serves:
--   elected from      state senators and representatives (district number), U.S. representatives (district
--                     of the Congress in session)
--   judicial circuit  circuit and associate circuit judges: every county of their circuit
--   mayor of          mayors: the place whose name matches their title ("Mayor Of Saint Louis" -> St. Louis)
--   appellate district  Court of Appeals judges: every county of the district in their title
--   federal district  U.S. district judges: every county of E.D. and/or W.D. Mo. (district 'moed', 'mowd',
--                     'moed+mowd')
-- Statewide offices (executives, U.S. senators, Supreme Court) and the Eighth Circuit serve every area and have
-- no rows.
with officials as (
    select
        official_id,
        office,
        district,
        {{ dbt.safe_cast('district', dbt.type_int()) }} as district_number,
        case
            when lower(office_title) like '%eastern district%' then 'eastern'
            when lower(office_title) like '%southern district%' then 'southern'
            when lower(office_title) like '%western district%' then 'western'
        end as appeals_district,
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

union all

select
    o.official_id,
    d.district_id,
    o.office,
    'appellate district' as relation
from officials as o
inner join districts as d
    on
        d.district_type = 'county'
        and o.appeals_district = d.appeals_district
where o.office = 'mo_court_of_appeals'

union all

select
    o.official_id,
    d.district_id,
    o.office,
    'federal district' as relation
from officials as o
inner join districts as d
    on
        d.district_type = 'county'
        and {{ dbt.position('d.federal_district', 'o.district') }} > 0
where o.office = 'us_district_court'
