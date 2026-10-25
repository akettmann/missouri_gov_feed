-- Sanity check: sessions with more than 5,000 bills and resolutions in fct_bills. The most through 2026 is 3,157 (the
-- 2026 regular session: 2,102 House, 1,055 Senate, resolutions included); more means a session's bills were
-- landed twice or the House and Senate lists stopped agreeing on bill numbers.
select
    session_code,
    count(*) as bills
from {{ ref('fct_bills') }}
group by session_code
having count(*) > 5000
