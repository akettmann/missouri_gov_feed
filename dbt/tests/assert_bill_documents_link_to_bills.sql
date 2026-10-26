-- Every document row belongs to a bill in fct_bills; a new orphan anywhere fails this test.
select
    d.session_code,
    d.bill
from {{ ref('fct_bill_documents') }} as d
left join {{ ref('fct_bills') }} as b
    on d.session_code = b.session_code and d.bill = b.bill
where b.bill is null
group by d.session_code, d.bill
