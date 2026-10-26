-- Who held which legislative seat in which year under which id, before ids are reconciled: the evidence
-- int_officials__person_ids works from. One row per (id as the source gave it, year, office, district,
-- House member id) for the
-- years with a House roster, from the House's own roster (its raw seat-matched key: an Open States id or
-- mohouse:<House member id>) and from Open States seat-terms (both chambers). A term counts for a year when it
-- runs past January 15 of it, and terms with an undated start are left out, as in int_officeholders__years.
-- house_member_id is the MO House member id the roster gave the row (null for Open States seat-terms): the House keeps
-- one member id per person across sessions and name changes, so the person-id rule can follow it. name_key is the
-- id's own full name. term_start/term_end are the Open States term's dates exactly as Open States
-- gives them (DATE; end 9999-12-31 while open; null for House roster rows, which carry only a year), so a rule can
-- tell overlap from succession. They are not the January-1 adjusted dates used for the year membership above:
-- those would make a January successor (from Jan 1) overlap a predecessor Open States ends on Jan 6-9.
-- The year before the first roster year is included too (Open States seat-terms only), so a member whose seat ended the
-- December before the roster begins still has evidence to be joined by (#504).
-- Known edge: the min(start)/max(end) collapse per (alias_id, year, office, district) spans any gap if one id holds
-- the same seat in two separate terms in a year.
with roster_years as (
    select distinct session_year as year
    from {{ ref('int_mo_house__member_seat_keys') }}
),

-- the roster years plus the year before the first one: a member whose seat ended the December before the first
-- roster (Stephen Webber, House to 2016-12-31, Senate from 2025) would otherwise leave no evidence at all and keep
-- an id of his own, apart from every later id (#504). Only Open States seat-terms count in that year.
all_years as (
    select year from roster_years
    union
    select min(year) - 1 as year from roster_years
),

years as (
    select
        year,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('year', dbt.type_string()), "'-01-15'"]), 'date') }}
            as handover_date,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('year', dbt.type_string()), "'-12-31'"]), 'date') }}
            as year_end
    from all_years
),

house_terms as (
    select
        m.raw_person_key as alias_id,
        m.session_year as year,
        'state_house' as office,
        {{ dbt.safe_cast('m.district_number', dbt.type_string()) }} as district,
        coalesce(p.full_name, m.full_name) as full_name,
        m.house_member_id,
        {{ dbt.safe_cast('null', 'date') }} as term_start,
        {{ dbt.safe_cast('null', 'date') }} as term_end
    from {{ ref('int_mo_house__member_seat_keys') }} as m
    left join {{ ref('stg_openstates__people') }} as p on m.openstates_id = p.openstates_id
),

seat_terms as (
    select
        s.openstates_id as alias_id,
        y.year,
        case s.chamber when 'upper' then 'state_senate' else 'state_house' end as office,
        {{ dbt.safe_cast('s.district_number', dbt.type_string()) }} as district,
        s.full_name,
        {{ dbt.safe_cast('null', dbt.type_string()) }} as house_member_id,
        {{ dbt.safe_cast('s.source_start_date', 'date') }} as term_start,
        {{ dbt.safe_cast('s.source_end_date', 'date') }} as term_end
    from {{ ref('int_mo_legislators__seat_terms') }} as s
    inner join years as y on s.start_date <= y.year_end and s.end_date > y.handover_date
    -- int_mo_legislators__seat_terms puts undated starts at 1900-01-01: their first year is unknown, so they are no
    -- evidence of the years they would span
    where s.start_date > {{ dbt.safe_cast("'1900-01-01'", 'date') }}
),

unioned as (
    select * from house_terms
    union all
    select * from seat_terms
)

select
    alias_id,
    year,
    office,
    district,
    house_member_id,
    max({{ mogov.name_key('full_name') }}) as name_key,
    min(term_start) as term_start,
    max(term_end) as term_end
from unioned
group by alias_id, year, office, district, house_member_id
