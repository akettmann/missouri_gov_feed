-- Contact data stays out of the marts: hearing comments and locations carry no email address or phone number
-- (staging replaces them with a marker, mogov.redact_contact).
select
    session_code,
    bill,
    hearing_index
from {{ ref('fct_bill_hearings') }}
where {{ mogov.has_contact_string('comments') }} or {{ mogov.has_contact_string('location') }}
