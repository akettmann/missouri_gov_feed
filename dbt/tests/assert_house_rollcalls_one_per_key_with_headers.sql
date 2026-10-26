-- Sanity checks on the House roll calls that survive staging (#435): the PDF header's General Assembly and session
-- label parse for every row (a null would let a misfiled PDF slip past the session check), and each
-- (session, day, roll-call number) appears once (the House sometimes publishes one roll call under two file names).
select
    session_code,
    session_day,
    rollcall_number,
    count(*) as pdfs,
    count(header_general_assembly) as with_general_assembly,
    count(header_session_label) as with_session_label
from {{ ref('stg_mo_house__rollcalls') }}
group by session_code, session_day, rollcall_number
having
    count(*) > 1
    or count(header_general_assembly) < count(*)
    or count(header_session_label) < count(*)
