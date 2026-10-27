-- Sanity check: more than 150 Senate bills (SB) signed in one session. Missouri enacts roughly 100 to 200 bills a
-- session, House and Senate bills together, so more than 150 from the Senate alone means the Senate's action wording
-- is being over-mapped to "signed" (a substitute or enrollment step read as the Governor's signature).
select
    session_code,
    count(*) as signed_senate_bills
from {{ ref('int_bills__status') }}
where
    bill_type = 'SB'
    and status in ('signed', 'signed with line-item vetoes', 'veto overridden')
group by session_code
having count(*) > 150
