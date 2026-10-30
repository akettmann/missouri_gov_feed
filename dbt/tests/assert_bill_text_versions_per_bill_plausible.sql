-- Sanity check: more than 25 text versions on one bill. The most through 2026 is 8 (introduced, committee
-- substitutes, perfected, truly agreed, ...); more means a staging model fanned out or the XML started listing
-- every link many times over.
select
    session_code,
    bill,
    count(*) as text_versions
from {{ ref('fct_bill_documents') }}
where document_kind = 'bill_text'
group by session_code, bill
having count(*) > 25
