-- Every Missouri legislative seat-term in Open States (current and retired people), keyed for matching:
-- chamber, district number, surname key, and date range (open-ended where Open States has no date).
-- Two corrections to Open States:
--   * a term starting in January counts from January 1. Open States starts the 2017 class on January 11,
--     but the session (and their votes) began January 4.
--   * seed legislator_seat_corrections adds terms Open States lacks or cuts short (senators who left
--     mid-term for statewide office), each with its source.
with roles as (
    select
        openstates_id,
        role_type as chamber,
        district,
        start_date,
        end_date
    from {{ ref('stg_openstates__roles') }}
    where role_type in ('upper', 'lower')
    union all
    select
        openstates_id,
        chamber,
        {{ dbt.safe_cast('district', dbt.type_string()) }} as district,
        {{ dbt.safe_cast('start_date', 'date') }} as start_date,
        {{ dbt.safe_cast('end_date', 'date') }} as end_date
    from {{ ref('legislator_seat_corrections') }}
)

select
    r.openstates_id,
    p.full_name,
    p.family_name,
    p.party,
    {{ mogov.name_key('p.family_name') }} as surname_key,
    {{ mogov.name_key('p.full_name') }} as full_name_key,
    r.chamber,
    {{ dbt.safe_cast('r.district', dbt.type_int()) }} as district_number,
    case
        when r.start_date is null then {{ dbt.safe_cast("'1900-01-01'", 'date') }}
        when extract(month from r.start_date) = 1 then {{ dbt.date_trunc('year', 'r.start_date') }}
        else r.start_date
    end as start_date,
    coalesce(r.end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date
from roles as r
inner join {{ ref('stg_openstates__people') }} as p on r.openstates_id = p.openstates_id
