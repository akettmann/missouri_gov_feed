-- Each law (type and number) in the federal sponsorship fact belongs to exactly one bill. GovInfo lists some laws under
-- two bills (119-hr-766 and 119-s-766 both list Public Law 119-120, #729); only the bill whose actions record
-- enactment may carry the law. Returns a row per law credited to more than one bill.
select
    law_type || ' ' || law_number as problem_key,
    count(distinct bill_id) as bills
from {{ ref('fct_federal_sponsorship') }}
where became_law
group by law_type, law_number
having count(distinct bill_id) > 1
