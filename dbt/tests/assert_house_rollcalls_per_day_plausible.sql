-- Sanity check: session days with more than 200 House roll calls. The most seen through 2026 is 95 (an end of
-- session day), so more means the loader is double-counting or misreading PDF numbers.
select
    session_code,
    session_day,
    count(*) as rollcalls
from {{ ref('stg_mo_house__rollcalls') }}
group by session_code, session_day
having count(*) > 200
