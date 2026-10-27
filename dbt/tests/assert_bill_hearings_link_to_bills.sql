-- Every hearing row belongs to a bill in fct_bills; a new orphan anywhere fails this test.
select
    h.session_code,
    h.bill
from {{ ref('fct_bill_hearings') }} as h
left join {{ ref('fct_bills') }} as b
    on h.session_code = b.session_code and h.bill = b.bill
where b.bill is null
group by h.session_code, h.bill
