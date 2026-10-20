-- The subject index terms of each bill, one row per term, for grouping votes by topic (join fct_vote_bills).
-- House bills carry the House XML's terms from the 2024 sessions on; earlier House bills that reached the
-- Senate, and Senate bills, carry the Senate topical index's (int_bills__subjects).
select
    session_code,
    bill,
    subject_id,
    subject_name,
    subject_source
from {{ ref('int_bills__subjects') }}
