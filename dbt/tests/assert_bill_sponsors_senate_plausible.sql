-- Sanity check on the Senate bills' sponsors in fct_bill_sponsors (#839): a Senate bill (bill starts with S) has at
-- most one primary sponsor and no other sponsor type (the Senate list has no co-sponsors), its sponsor_chamber is
-- state_senate, and its district is one of the 34 senate districts. A Senate bill from a session the list covers must
-- have a sponsor row (bills with no sponsor on the list are the only ones missing, and there are only a few).
select
    session_code,
    bill,
    'more than one sponsor row' as problem
from {{ ref('fct_bill_sponsors') }}
where left(bill, 1) = 'S'
group by session_code, bill
having count(*) > 1

union all

select
    session_code,
    bill,
    'not a state_senate Sponsor in districts 1-34' as problem
from {{ ref('fct_bill_sponsors') }}
where
    left(bill, 1) = 'S'
    and (
        sponsor_type <> 'Sponsor'
        or sponsor_chamber <> 'state_senate'
        or sponsor_district not between 1 and 34
    )
