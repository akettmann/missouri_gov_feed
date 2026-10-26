-- One row per MO House bill per session (House XML export): number, current version, titles, last action.
-- source_url is the link on the bill's first listed action (the bill's page on house.mo.gov).
select
    b.session_code,
    2000 + {{ dbt.safe_cast('left(b.session_code, 2)', dbt.type_int()) }} as session_year,
    b.bill,
    b.current_bill_string,
    b.short_title,
    b.long_title,
    b.last_action,
    b.proposed_effective_date,
    a.link as source_url
from {{ source('mo_house', 'xml_bills') }} as b
left join {{ source('mo_house', 'xml_bill_actions') }} as a
    on b.session_code = a.session_code and b.file_name = a.file_name and a.action_index = 1
