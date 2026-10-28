{{ config(severity='warn') }}
-- Sanity check for rpt_statute_section_bills: it shows one primary sponsor per bill (the smallest official_id when
-- there are several). A bill with more than one 'Sponsor' row in fct_bill_sponsors means that choice is hiding a
-- sponsor, so warn and look at the source.
select
    session_code,
    bill,
    count(*) as primary_sponsor_rows
from {{ ref('fct_bill_sponsors') }}
where sponsor_type = 'Sponsor'
group by session_code, bill
having count(*) > 1
