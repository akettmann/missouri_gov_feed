-- Sanity check: more than 300 documents of one kind on one bill. The most through 2026 is 73 (amendments on one
-- bill; every other kind has at most 9 per bill); more means a staging model fanned out (a join repeated rows) or
-- the XML started listing a bill's links many times over.
select
    session_code,
    bill,
    document_kind,
    count(*) as documents
from {{ ref('fct_bill_documents') }}
group by session_code, bill, document_kind
having count(*) > 300
