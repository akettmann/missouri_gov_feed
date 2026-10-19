{{ config(enabled=var('mec_direct', false)) }}
-- Cover-page totals of every campaign finance report filed by an official's state committees (MEC direct
-- export, report years 2023+): raised and spent in the period and the election to date, money on hand and
-- debt. The quick "raised $X, spent $Y, $Z in the bank" view without summing itemized rows. Amended
-- reports are separate rows (report_name starts "AMENDED"); "Limited Activity" reports carry no amounts.
select
    m.official_id,
    m.committee_name,
    r.mec_committee_id,
    r.report_id,
    r.report_name,
    r.report_year,
    r.report_type,
    r.contributions_received,
    r.loans_received,
    r.misc_receipts,
    r.inkind_contributions_received,
    r.total_receipts_this_election,
    r.expenditures_this_period,
    r.total_expenditures_this_election,
    r.contributions_made_this_period,
    r.total_contributions_made_this_election,
    r.starting_money_on_hand,
    r.ending_money_on_hand,
    r.outstanding_indebtedness,
    m.confidence as match_confidence,
    'https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=' || r.mec_committee_id as source_url
from {{ ref('stg_mec_direct__report_summaries') }} as r
inner join {{ ref('int_mec__official_committees') }} as m on r.mec_committee_id = m.mec_committee_id
