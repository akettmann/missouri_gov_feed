{{ config(severity='warn') }}
-- Warn-level companion to assert_bill_hearings_no_contact_data (#711): that guard shares the redaction pattern, so
-- it cannot see a format the pattern deliberately skips (a spaced or dotted 7-digit number such as 751.6662, a long
-- run of digits). This flags any such digit run left in the hearing comments or locations for a human to look at.
select
    session_code,
    bill,
    hearing_index
from {{ ref('fct_bill_hearings') }}
where {{ mogov.has_phone_like_digits('comments') }} or {{ mogov.has_phone_like_digits('location') }}
