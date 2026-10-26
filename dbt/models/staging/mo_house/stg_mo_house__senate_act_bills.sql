-- One row per Senate bill the House XML's SenateActList (2024 on) lists as having reached the House: number, current
-- version, titles, last action, proposed effective date and the Senate sponsor. The list covers regular and special
-- sessions alike; it has no subjects and no bill-page link. Older sessions have no SenateActList.
select
    session_code,
    2000 + {{ dbt.safe_cast('left(session_code, 2)', dbt.type_int()) }} as session_year,
    bill,
    current_bill_string,
    short_title,
    long_title,
    last_action,
    proposed_effective_date,
    sponsor_name
from {{ source('mo_house', 'xml_senate_act_bills') }}
