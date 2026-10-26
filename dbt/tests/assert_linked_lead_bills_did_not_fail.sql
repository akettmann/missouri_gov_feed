-- Sanity check: a lead bill that the Revisor credits with changing statute cannot have failed. The Revisor records an
-- act once it is law, so a linked bill whose House actions end in "failed" is either not the lead of its combined act
-- ("A.L. 2023 H.B. 115 & 99": HB99 never passed; the 19 such House bills since 2017 are not lead bills) or its session
-- code is wrong (an extraordinary session read as the regular one).
select
    l.session_code,
    l.bill,
    b.outcome
from {{ ref('fct_bill_statute_links') }} as l
inner join {{ ref('fct_bills') }} as b on l.session_code = b.session_code and l.bill = b.bill
where l.is_lead_bill and b.outcome = 'failed'
