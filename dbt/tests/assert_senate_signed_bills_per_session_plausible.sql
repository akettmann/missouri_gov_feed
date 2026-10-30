-- Sanity check: more than 100 Senate bills (SB) signed in one session. Missouri enacts roughly 100 to 200 bills a
-- session, House and Senate bills together, so a Senate count near that total means the Senate's action wording is
-- being over-mapped to "signed" (a substitute or enrollment step read as the Governor's signature). The cap sits
-- above the real maximum, not at the edge of it: counting the SBs the Revisor's session-law histories name (an
-- upper bound, it includes SBs folded into another bill), the most in 2016-2026 is 63 (2018), then 57 (2016) and
-- 41 (2019); signed SBs measured directly are 38 (2026), 27 (2025), 14 (2024) and 13 in the 2018 quarter sample.
-- 100 leaves room for a busy session and still fails when a mapping signs most Senate bills (#715).
select
    session_code,
    count(*) as signed_senate_bills
from {{ ref('int_bills__status') }}
where
    bill_type = 'SB'
    and status in ('signed', 'signed with line-item vetoes', 'veto overridden')
group by session_code
having count(*) > 100
