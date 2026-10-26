-- Every bill a state vote was linked to (fct_vote_bills) is a bill in fct_bills. A row returned here is a vote that
-- links to a bill number fct_bills lacks: e.g. a special-session Senate bill that fct_bills left out
-- (#438: 253 SB1, SB3 and SB4, which only the House XML's SenateActList records).
select
    v.chamber,
    v.vote_id,
    v.session_code,
    v.bill
from {{ ref('fct_vote_bills') }} as v
left join {{ ref('fct_bills') }} as b on v.session_code = b.session_code and v.bill = b.bill
where b.bill is null
