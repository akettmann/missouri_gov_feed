{{ config(enabled=var('mec_direct', false)) }}
-- MEC campaign finance report cover pages (direct export): one row per filed report with its totals.
-- "This election" totals accumulate across an election's reports; "this period" amounts cover the report
-- alone. Amended reports are separate rows with their own report_id.
select
    reportid as report_id,
    coverpageid as cover_page_id,
    mecid as mec_committee_id,
    committee_name,
    report as report_name,
    {{ dbt.safe_cast('report_year', dbt.type_int()) }} as report_year,
    report_type,
    {{ dbt.safe_cast('contributions_received', dbt.type_numeric()) }} as contributions_received,
    {{ dbt.safe_cast('loans_received', dbt.type_numeric()) }} as loans_received,
    {{ dbt.safe_cast('misc_receipts', dbt.type_numeric()) }} as misc_receipts,
    {{ dbt.safe_cast('inkind_contributions', dbt.type_numeric()) }} as inkind_contributions_received,
    {{ dbt.safe_cast('total_receipts_this_election', dbt.type_numeric()) }} as total_receipts_this_election,
    {{ dbt.safe_cast('expenditure_subtotal', dbt.type_numeric()) }} as expenditures_this_period,
    {{ dbt.safe_cast('total_expenditures', dbt.type_numeric()) }} as total_expenditures_this_election,
    {{ dbt.safe_cast('contribution_subtotal', dbt.type_numeric()) }} as contributions_made_this_period,
    {{ dbt.safe_cast('total_contributions', dbt.type_numeric()) }} as total_contributions_made_this_election,
    {{ dbt.safe_cast('starting_money_on_hand', dbt.type_numeric()) }} as starting_money_on_hand,
    {{ dbt.safe_cast('ending_money_on_hand', dbt.type_numeric()) }} as ending_money_on_hand,
    {{ dbt.safe_cast('outstanding_indebtedness', dbt.type_numeric()) }} as outstanding_indebtedness
from {{ source('raw', 'mec_summary') }}
