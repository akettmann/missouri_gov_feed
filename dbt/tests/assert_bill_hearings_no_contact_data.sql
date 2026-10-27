-- Contact data stays out of the marts: hearing comments and locations carry no email address.
select
    session_code,
    bill,
    hearing_index
from {{ ref('fct_bill_hearings') }}
where comments like '%@%' or location like '%@%'
