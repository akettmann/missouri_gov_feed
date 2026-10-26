-- Amendments offered to a bill, for House bills and for the Senate bills the House acted on (SenateActList). One row
-- per amendment listing in the XML, not per amendment: the XML lists 112 amendments twice (adjacent amendment_index,
-- same amendment_url, lr_number, description and status; only sponsor differs), so the real key is
-- (session_code, bill, amendment_url). amendment_url is the amendment's PDF (the XML's AmendmentText, which holds a
-- link, not text); map_url is the amendment's change map PDF, present on very few. The raw sort_value is not staged:
-- it only restates lr_number (see docs/sources.md).
select
    b.session_code,
    b.bill,
    c.amendment_index,
    c.description,
    c.lr_number,
    c.sponsor,
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
    status,
    status_description,
    amendment_text as amendment_url,
    map_link as map_url
from {{ source('mo_house', 'xml_senate_act_amendments') }}
