-- Sanity check: a Senate bill the Governor signed or vetoed was first "Truly Agreed To and Finally Passed" in the
-- Senate's own history (the enrolled bill goes to the Governor only then). Returns any bill with a governor
-- action and no truly-agreed action: a mis-mapped wording or an action list that lost its middle.
select
    session_code,
    bill
from {{ ref('stg_mo_senate__bill_actions') }}
where session_code is not null
group by session_code, bill
having
    max(case when action like 'Signed by Governor%' or action like 'Vetoed by Governor%' then 1 else 0 end) = 1
    and max(case when action = 'Truly Agreed To and Finally Passed' then 1 else 0 end) = 0
