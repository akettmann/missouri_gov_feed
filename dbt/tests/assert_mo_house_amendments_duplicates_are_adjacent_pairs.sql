-- Sanity check on the grain of stg_mo_house__bill_amendments: the same amendment_url may be listed more than once on a
-- bill only as the known pair (112 on current data): two rows with adjacent amendment_index, the same lr_number,
-- description and status, and different sponsors (only sponsor differs). Anything else (a triple, a gap, differing
-- fields, identical sponsors i.e. an exact duplicate) means the XML changed shape or two amendments share a PDF, so
-- look before collapsing them. Comparisons are NULL-safe: a value on one listing and NULL on the other counts as
-- differing, and two NULL sponsors count as identical.
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
        or count(distinct coalesce(lr_number, '<null>')) > 1
        or count(distinct coalesce(description, '<null>')) > 1
        or count(distinct coalesce(status, '<null>')) > 1
        or count(distinct coalesce(sponsor, '<null>')) < 2
    )
