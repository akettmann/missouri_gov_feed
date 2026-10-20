-- One row per MO House bill per session (House XML export): number, current version, titles, last action.
-- bill_doc keeps the bill's XML-as-JSON for the subject, sponsor and roll-call models built on this one.
with src as (
    select
        {{ mogov.json_str('payload', '$.session_code') }} as session_code,
        {{ mogov.json_str('payload', '$.bill') }} as bill,
        {{ mogov.json_fragment('payload', '$.doc.BillInformation[0]') }} as bill_doc
    from {{ source('mo_house', 'bills') }}
)

select
    session_code,
    2000 + {{ dbt.safe_cast('left(session_code, 2)', dbt.type_int()) }} as session_year,
    bill,
    {{ mogov.json_str('bill_doc', '$.CurrentBillString[0]') }} as current_bill_string,
    {{ mogov.json_str('bill_doc', '$.Title[0].ShortTitle[0]') }} as short_title,
    {{ mogov.json_str('bill_doc', '$.Title[0].LongTitle[0]') }} as long_title,
    {{ mogov.json_str('bill_doc', '$.LastAction[0]') }} as last_action,
    {{ dbt.safe_cast(mogov.json_str('bill_doc', '$.ProposedEffectiveDate[0]'), 'date') }} as proposed_effective_date,
    {{ mogov.json_str('bill_doc', '$.Action[0].Link[0]') }} as source_url,
    bill_doc
from src
