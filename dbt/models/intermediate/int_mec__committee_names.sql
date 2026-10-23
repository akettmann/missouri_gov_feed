-- Every name a Missouri committee has filed under, with the years the committee was active (filed a
-- report, received or spent money, or was registered for an election), from both MEC feeds. A committee
-- that changes its name keeps its MECID, so one ID can carry several names; a name reused by a new committee
-- after the old one closed maps to several IDs, told apart by their active years.
-- Years outside 2000..next year are typos in the source dates and are ignored. MECIDs are upper-cased.
with sightings as (
    select
        mec_committee_id,
        committee_name,
        contribution_year as active_year
    from {{ ref('int_mec__contributions_received') }}
    union all
    select
        mec_committee_id,
        committee_name,
        expenditure_year as active_year
    from {{ ref('stg_tap_mec__expenditures') }}
    {% if var('mec_direct', false) %}
        union all
        select
            mec_committee_id,
            committee_name,
            report_year as active_year
        from {{ ref('stg_mec__report_summaries') }}
        union all
        select
            mec_committee_id,
            committee_name,
            cast(extract(year from expenditure_date) as {{ dbt.type_int() }}) as active_year
        from {{ ref('stg_mec__expenditures') }}
        union all
        select
            mec_committee_id,
            committee_name,
            cast(extract(year from contribution_date) as {{ dbt.type_int() }}) as active_year
        from {{ ref('stg_mec__contributions_made') }}
        union all
        select
            mec_committee_id,
            committee_name,
            cast(extract(year from election_date) as {{ dbt.type_int() }}) as active_year
        from {{ ref('stg_mec__candidate_committees') }}
    {% endif %}
),

plausible as (
    select
        upper(trim(mec_committee_id)) as mec_committee_id,
        trim(committee_name) as committee_name,
        case
            when
                active_year between 2000 and cast(
                    extract(year from {{ dbt.current_timestamp() }}) as {{ dbt.type_int() }}
                )
                + 1
                then active_year
        end as active_year
    from sightings
    where mec_committee_id is not null and trim(committee_name) <> ''
),

committee_years as (
    select
        mec_committee_id,
        min(active_year) as first_active_year,
        max(active_year) as last_active_year
    from plausible
    group by mec_committee_id
)

select
    n.mec_committee_id,
    n.committee_name,
    y.first_active_year,
    y.last_active_year,
    max(n.active_year) as last_year_under_name
from plausible as n
inner join committee_years as y on n.mec_committee_id = y.mec_committee_id
group by n.mec_committee_id, n.committee_name, y.first_active_year, y.last_active_year
