-- Sanity check on the grain of stg_mo_house__bill_amendments: the same amendment_url may be listed more than once on a
-- bill only as the known pair (112 on current data): two rows with adjacent amendment_index and the same lr_number,
-- description and status (only sponsor differs). Anything else (a triple, a gap, differing fields) means the XML
-- changed shape or two amendments share a PDF, so look before collapsing them.
select
    session_code,
    bill,
    amendment_url,
    count(*) as listings
from {{ ref('stg_mo_house__bill_amendments') }}
group by session_code, bill, amendment_url
having
    count(*) > 1
    and (
        count(*) > 2
        or max(amendment_index) - min(amendment_index) <> 1
        or count(distinct lr_number) > 1
        or count(distinct description) > 1
        or count(distinct status) > 1
    )
