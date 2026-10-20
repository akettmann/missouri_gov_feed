-- The officials list by year, for the browse page's year control. The current calendar year is everyone
-- serving now (dim_official, every tracked office). Earlier years are the past holders of the offices with
-- dated rosters (int_officeholders__years: MO House and Senate, Congress, federal judges); other offices
-- have no rows before the current year. has_profile marks people with a profile page (anyone serving now,
-- in any office), so a past legislator who is a judge or statewide officer today still links to it.
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
        'dim_official' as source
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
        h.source
    from {{ ref('int_officeholders__years') }} as h
    inner join this_year as y on h.year < y.year
),

unioned as (
    select * from current_officials
    union all
    select * from past
)

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
    u.source
from unioned as u
left join (select distinct official_id from {{ ref('dim_official') }}) as p on u.official_id = p.official_id
