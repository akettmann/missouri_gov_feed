-- Committee hearings noticed for each bill, for House bills and for the Senate bills the House acted on
-- (SenateActList, 2024 sessions on). One row per hearing notice, in the order the House lists them.
-- A hearing that was moved is listed again under a new notice (the comments say "Rescheduled" or "Time change"),
-- so a bill can show two notices for one day; the House XML carries no cancelled flag.
-- notice_time is the clock time as HH:MM, null when the House gave only the free-text alt_time ("4:30 PM or upon
-- adjournment"; the XML stores that as midnight). Midnight without an alt_time is kept as 00:00 (not seen so far).
-- Email addresses and phone numbers in comments and locations are replaced by a marker ("[email removed]",
-- "[phone removed]", mogov.redact_contact): committee staff and members put contact details there, and this
-- project keeps contact data out of the models. The rest of the text stays.
with hearings as (
    select
        b.session_code,
        b.bill,
        c.hearing_index,
        c.committee_name,
        c.notice_date,
        c.notice_time,
        c.alt_time,
        c.location,
        c.comments
    from {{ source('mo_house', 'xml_bill_hearings') }} as c
    inner join {{ source('mo_house', 'xml_bills') }} as b
        on c.session_code = b.session_code and c.file_name = b.file_name

    union all

    select
        session_code,
        bill,
        hearing_index,
        committee_name,
        notice_date,
        notice_time,
        alt_time,
        location,
        comments
    from {{ source('mo_house', 'xml_senate_act_hearings') }}
)

select
    session_code,
    2000 + {{ dbt.safe_cast('left(session_code, 2)', dbt.type_int()) }} as session_year,
    bill,
    hearing_index,
    committee_name,
    notice_date as hearing_date,
    case
        when alt_time is not null and substr(notice_time, 12, 5) = '00:00' then null
        else substr(notice_time, 12, 5)
    end as hearing_time,
    alt_time as hearing_time_note,
    {{ mogov.redact_contact('location') }} as location,
    {{ mogov.redact_contact('comments') }} as comments
from hearings
