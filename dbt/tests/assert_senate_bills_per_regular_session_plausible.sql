-- Sanity check on the Senate's own bill list. A regular session has had 797 to 975 Senate bills (SB) in 2024 to 2026
-- (another 40 to 90 resolutions); fewer than 400 means a partial landing, more than 2,000 a session landed twice
-- under different keys. A special session is small by nature and is not checked here.
select
    session_year,
    count(*) as senate_bills
from {{ ref('stg_mo_senate__bills') }}
where session_type = 'R' and bill_prefix = 'SB'
group by session_year
having count(*) < 400 or count(*) > 2000
