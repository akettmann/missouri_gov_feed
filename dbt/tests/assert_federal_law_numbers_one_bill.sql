-- Each law (type and number: Public Law 119-1 and Private Law 119-1 are different laws) belongs to exactly one bill
-- among the bills that became law. The BILLSTATUS laws list can credit a law to the wrong bill (119-hr-766 lists
-- Public Law 119-120, which is 119 S. 766, #729); became_law comes from the actions, so such a bill must not be
-- became_law. Returns a row per law claimed by more than one became_law bill.
select
    l.law_type || ' ' || l.law_number as problem_key,
    count(distinct s.bill_id) as bills
from {{ ref('stg_govinfo_billstatus__laws') }} as l
inner join {{ ref('int_federal_bills__stage') }} as s on l.bill_id = s.bill_id
where s.stage = 'became_law'
group by l.law_type, l.law_number
having count(distinct s.bill_id) > 1
