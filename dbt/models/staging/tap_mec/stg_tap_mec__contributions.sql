-- MEC itemized contributions received by Missouri committees (TAP mirror, 2011-2022).
-- The mirror combines two MEC export layouts; coalesce the overlapping columns. dupe_flag marks rows TAP
-- identified as duplicates (amended reports) and they're dropped.
-- The second layout (2020-2022) has no ctrb_name / ctrb_type: a committee donor is named in `committee`, an
-- organization in `company`, a person in first/last name (blank strings, not nulls, when absent).
-- Placeholder donor names (#31): ~10k rows carry a one-character ctrb_name / committee ('C', '~', '0', '-', 'x',
-- '_'), almost all with a person's first/last name (federal-committee filings transferred to MEC). A name shorter
-- than 2 characters is treated as missing, so the name falls back to the person's name and the row is typed
-- Individual. With no person's name either, the name stays null and the reported type is kept.
with

source_rows as (
    select
        *,
        case when length(trim(ctrb_name)) >= 2 then trim(ctrb_name) end as ctrb_name_clean,
        case when length(trim(committee)) >= 2 then trim(committee) end as committee_clean,
        nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), '') as person_name
    from {{ source('tap_mec', 'contributions') }}
    where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
)

select
    coalesce(cmte_id, mecid) as mec_committee_id,
    coalesce(cmte_name, committee_name) as committee_name,
    coalesce(
        ctrb_name_clean,
        committee_clean,
        person_name,
        nullif(trim(company), '')
    ) as contributor_name,
    case
        when ctrb_name is not null and ctrb_name_clean is null and person_name is not null then 'Individual'
        else coalesce(
            ctrb_type,
            case
                when committee_clean is not null then 'Committee'
                when nullif(trim(company), '') is not null then 'Organization'
                else 'Individual'
            end
        )
    end as contributor_type,
    -- the donor committee's name as reported (no MECID: mec_committee_id is the receiving committee's)
    case
        when ctrb_type = 'Committee' then ctrb_name_clean
        when ctrb_type is null then committee_clean
    end as contributor_committee_name,
    company as contributor_company,
    employer as contributor_employer,
    occupation as contributor_occupation,
    coalesce(city_clean, city) as contributor_city,
    coalesce(state_clean, state) as contributor_state,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ dbt.safe_cast('date', 'date') }} as contribution_date,
    {{ dbt.safe_cast('year', dbt.type_int()) }} as contribution_year,
    coalesce(cont_type, contribution_type) as contribution_kind,
    coalesce(rpt_type, report) as report
from source_rows
