-- Sanity check: more than 150 amendment links on one Senate bill. The sample through 2026 has at most a few dozen
-- (a heavily amended omnibus bill); more means a staging model fanned out (a join repeated rows) or the page started
-- listing every amendment of the session on each bill. Text versions per bill are bounded by
-- assert_bill_text_versions_per_bill_plausible (25).
select
    session_code,
    bill,
    count(*) as amendments
from {{ ref('fct_bill_documents') }}
where source_site = 'senate' and document_kind = 'amendment'
group by session_code, bill
having count(*) > 150
