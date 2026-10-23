-- MEC itemized contributions received by Missouri committees (TAP mirror, 2011-2022).
-- The mirror combines two MEC export layouts; coalesce the overlapping columns. dupe_flag marks rows TAP
-- identified as duplicates (amended reports) and they're dropped.
-- The second layout (2020-2022) has no ctrb_name / ctrb_type: a committee donor is named in `committee`, an
-- organization in `company`, a person in first/last name (blank strings, not nulls, when absent).
select
    coalesce(cmte_id, mecid) as mec_committee_id,
    coalesce(cmte_name, committee_name) as committee_name,
    coalesce(
        ctrb_name,
        nullif(trim(committee), ''),
        nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''),
        nullif(trim(company), '')
    ) as contributor_name,
    coalesce(
        ctrb_type,
        case
            when nullif(trim(committee), '') is not null then 'Committee'
            when nullif(trim(company), '') is not null then 'Organization'
            else 'Individual'
        end
    ) as contributor_type,
    -- the donor committee's name as reported (no MECID: mec_committee_id is the receiving committee's)
    case
        when ctrb_type = 'Committee' then trim(ctrb_name)
        when ctrb_type is null then nullif(trim(committee), '')
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
from {{ source('tap_mec', 'contributions') }}
where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
