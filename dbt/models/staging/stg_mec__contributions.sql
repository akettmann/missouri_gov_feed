-- MEC itemized contributions received by Missouri committees (TAP mirror, 2011-2022).
-- The mirror combines two MEC export layouts; coalesce the overlapping columns. dupe_flag marks rows TAP
-- identified as duplicates (amended reports) and they're dropped.
select
    coalesce(cmte_id, mecid) as mec_committee_id,
    coalesce(cmte_name, committee_name) as committee_name,
    coalesce(ctrb_name, trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), company) as contributor_name,
    coalesce(ctrb_type, case when company is not null then 'Organization' else 'Individual' end) as contributor_type,
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
from {{ source('raw', 'tap_mec_contributions') }}
where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
