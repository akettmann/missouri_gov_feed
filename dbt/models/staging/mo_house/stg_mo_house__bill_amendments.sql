-- Amendments offered to a bill with the link to the amendment's change map PDF, for House bills and for the Senate
-- bills the House acted on (SenateActList). One row per amendment.
select
    b.session_code,
    b.bill,
    c.amendment_index,
    c.description,
    c.lr_number,
    c.status,
    c.status_description,
    c.map_link as map_url
from {{ source('mo_house', 'xml_bill_amendments') }} as c
inner join {{ source('mo_house', 'xml_bills') }} as b
    on c.session_code = b.session_code and c.file_name = b.file_name
where c.map_link is not null

union all

select
    session_code,
    bill,
    amendment_index,
    description,
    lr_number,
    status,
    status_description,
    map_link as map_url
from {{ source('mo_house', 'xml_senate_act_amendments') }}
where map_link is not null
