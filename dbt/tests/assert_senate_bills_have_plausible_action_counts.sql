-- Sanity check on the Senate bill actions: no bill has more than 150 actions (every committee step, amendment and
-- both chambers' readings fit well under that). More means a bill's history was landed under another bill's key or
-- a session landed twice.
select
    session_year,
    session_type,
    bill_id,
    count(*) as actions
from {{ ref('stg_mo_senate__bill_actions') }}
group by session_year, session_type, bill_id
having count(*) > 150
