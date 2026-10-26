-- Amendments offered to a bill, for House bills and for the Senate bills the House acted on (SenateActList). One row
-- per amendment. amendment_url is the amendment's PDF (the XML's AmendmentText, which holds a link, not text); map_url
-- is the amendment's change map PDF, present on very few.
select
    b.session_code,
    b.bill,
    c.amendment_index,
    c.description,
    c.lr_number,
    c.sponsor,
    c.sort_value,
    c.status,
    c.status_description,
    c.amendment_text as amendment_url,
    c.map_link as map_url
from {{ source('mo_house', 'xml_bill_amendments') }} as c
inner join {{ source('mo_house', 'xml_bills') }} as b
    on c.session_code = b.session_code and c.file_name = b.file_name

union all

select
    session_code,
    bill,
    amendment_index,
    description,
    lr_number,
    sponsor,
    sort_value,
    status,
    status_description,
    amendment_text as amendment_url,
    map_link as map_url
from {{ source('mo_house', 'xml_senate_act_amendments') }}
