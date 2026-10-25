-- The officials list by year, for the browse page's year control. The current calendar year is everyone
-- serving now (dim_official, every tracked office). Earlier years are the past holders of the offices with
-- dated rosters (int_officeholders__years: MO House and Senate, Congress, federal judges); other offices
-- have no rows before the current year. has_profile marks people with a profile page (anyone serving now,
-- in any office), so a past legislator who is a judge or statewide officer today still links to it.
-- source_url is the roster behind a past row: the House's session export for that year, the Open States
-- folder (legislature, retired, ...) holding the person's file, the congress-legislators repository (one
-- dataset), or the judge's own FJC page; null for the current year, whose rows come from dim_official.
-- An Open States row with no matching person stays null, so the not_null test on source_url catches it.
with this_year as (
    select cast(extract(year from current_date) as {{ dbt.type_int() }}) as year
),

current_officials as (
    select
        y.year,
        d.official_id,
        d.full_name,
        d.party,
        d.level,
        d.office,
        d.office_title,
        d.district,
        'dim_official' as source,
        cast(null as {{ dbt.type_string() }}) as openstates_id
    from {{ ref('dim_official') }} as d
    cross join this_year as y
),

past as (
    select
        h.year,
        h.official_id,
        h.full_name,
        h.party,
        h.level,
        h.office,
        h.office_title,
        h.district,
        h.source,
        h.openstates_id
    from {{ ref('int_officeholders__years') }} as h
    inner join this_year as y on h.year < y.year
),

unioned as (
    select * from current_officials
    union all
    select * from past
)

{% set yy = dbt.right(dbt.safe_cast('u.year', dbt.type_string()), 2) %}
select
    cast(u.year as {{ dbt.type_int() }}) as year,
    u.official_id,
    u.full_name,
    u.party,
    u.level,
    u.office,
    u.office_title,
    u.district,
    p.official_id is not null as has_profile,
    u.source,
    case u.source
        when 'mo_house roster'
            then
                {{ dbt.concat(["'https://documents.house.mo.gov/xml/'", yy, "'1.zip'"]) }}
        when 'openstates'
            then 'https://github.com/openstates/people/tree/main/data/mo/' || o.folder
        when 'congress-legislators' then 'https://github.com/unitedstates/congress-legislators'
        when 'fjc' then 'https://www.fjc.gov/node/' || {{ dbt.replace('u.official_id', "'fjc:'", "''") }}
    end as source_url
from unioned as u
left join (select distinct official_id from {{ ref('dim_official') }}) as p on u.official_id = p.official_id
left join {{ ref('stg_openstates__people') }} as o on u.source = 'openstates' and u.openstates_id = o.openstates_id
