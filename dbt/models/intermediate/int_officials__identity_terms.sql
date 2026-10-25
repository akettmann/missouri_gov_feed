-- Who held which legislative seat in which year under which id, before ids are reconciled: the evidence
-- int_officials__person_ids works from. One row per (id as the source gave it, year, office, district) for the
-- years with a House roster, from the House's own roster (its raw seat-matched key: an Open States id or
-- mohouse:<House member id>) and from Open States seat-terms (both chambers). A term counts for a year when it
-- runs past January 15 of it, and terms with an undated start are left out, as in int_officeholders__years.
-- name_key is the id's own full name. Grain: one row per (alias_id, year, office, district).
with years as (
    select distinct
        session_year as year,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('session_year', dbt.type_string()), "'-01-15'"]), 'date') }}
            as handover_date,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('session_year', dbt.type_string()), "'-12-31'"]), 'date') }}
            as year_end
    from {{ ref('int_mo_house__member_seat_keys') }}
),

house_terms as (
    select
        m.raw_person_key as alias_id,
        m.session_year as year,
        'state_house' as office,
        {{ dbt.safe_cast('m.district_number', dbt.type_string()) }} as district,
        coalesce(p.full_name, m.full_name) as full_name
    from {{ ref('int_mo_house__member_seat_keys') }} as m
    left join {{ ref('stg_openstates__people') }} as p on m.openstates_id = p.openstates_id
),

seat_terms as (
    select
        s.openstates_id as alias_id,
        y.year,
        case s.chamber when 'upper' then 'state_senate' else 'state_house' end as office,
        {{ dbt.safe_cast('s.district_number', dbt.type_string()) }} as district,
        s.full_name
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
    max({{ mogov.name_key('full_name') }}) as name_key
from unioned
group by alias_id, year, office, district
