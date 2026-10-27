-- Sanity check on fct_bill_hearings: no bill has more than 15 hearing notices in a session (max 11 on current data,
-- SB890 in 2026; a moved hearing is noticed again) and none has more than 3 on one day (max 2). More means a
-- parser or grain problem (a hearing list repeated per bill, a bill key that merges bills).
with per_day as (
    select
        session_code,
        bill,
        hearing_date,
        count(*) as notices
    from {{ ref('fct_bill_hearings') }}
    group by session_code, bill, hearing_date
)

select
    session_code,
    bill,
    sum(notices) as hearings,
    max(notices) as max_notices_one_day
from per_day
group by session_code, bill
having sum(notices) > 15 or max(notices) > 3
