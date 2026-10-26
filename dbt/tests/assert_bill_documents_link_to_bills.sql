-- Every document row belongs to a bill in fct_bills. Known exception (#438): the House acted on two special-session
-- Senate bills (253 SB3 and SB4) that fct_bills does not list, so their documents have no bill row; a new orphan
-- anywhere else fails this test.
select
    d.session_code,
    d.bill
from {{ ref('fct_bill_documents') }} as d
left join {{ ref('fct_bills') }} as b
    on d.session_code = b.session_code and d.bill = b.bill
where
    b.bill is null
    and not (d.session_code = '253' and d.bill in ('SB3', 'SB4'))
group by d.session_code, d.bill
