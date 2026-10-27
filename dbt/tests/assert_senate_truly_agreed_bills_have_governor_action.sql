-- Sanity check (#237): in a session whose Senate history is loaded, every truly agreed Senate bill (SB) has a
-- governor action or delivery to the Secretary of State once its session is over. The House XML's list of a Senate
-- bill can stop at the speaker's signature (2024 SB 727); the Senate's own history carries "Signed by Governor" or
-- "Governor took no action, sent to Secretary of State". A bill still 'awaiting governor' is the current year's;
-- a Senate bill with no loaded Senate actions (its Actions tab was rejected, mo_senate_bills.fragment_rejected) is
-- not checked here.
select
    s.session_code,
    s.bill,
    s.outcome
from {{ ref('int_bills__status') }} as s
inner join (
    select distinct
        session_code,
        bill
    from {{ ref('stg_mo_senate__bill_actions') }}
    where session_code is not null
) as a on s.session_code = a.session_code and s.bill = a.bill
where
    s.bill_type = 'SB'
    and s.is_session_over
    and s.outcome = 'no governor action recorded'
