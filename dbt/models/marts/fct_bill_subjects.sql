-- The House subject index terms of each House bill, one row per term, for grouping votes by topic
-- (join fct_vote_bills). The House export carries them from the 2024 sessions on.
select distinct
    session_code,
    bill,
    subject_id,
    subject_name
from {{ ref('stg_mo_house__bill_subjects') }}
where subject_name is not null
