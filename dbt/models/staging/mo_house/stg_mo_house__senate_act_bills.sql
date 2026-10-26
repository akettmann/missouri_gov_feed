-- One row per Senate bill the House XML's SenateActList (2024 on) lists as having reached the House: number, current
-- version, titles, last action, proposed effective date and the Senate sponsor. The list covers regular and special
-- sessions alike; it has no subjects. source_url is the link on the bill's first listed action (the bill's page on
-- house.mo.gov), as for House bills. Older sessions have no SenateActList.
select
    b.session_code,
    2000 + {{ dbt.safe_cast('left(b.session_code, 2)', dbt.type_int()) }} as session_year,
    b.bill,
    b.current_bill_string,
    b.short_title,
    b.long_title,
    b.last_action,
    b.proposed_effective_date,
    b.sponsor_name,
    a.link as source_url
from {{ source('mo_house', 'xml_senate_act_bills') }} as b
left join {{ source('mo_house', 'xml_senate_act_actions') }} as a
    on b.session_code = a.session_code and b.bill = a.bill and a.action_index = 1
