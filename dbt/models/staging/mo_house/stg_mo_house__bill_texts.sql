-- Bill text versions with the links to the text PDF and the House's change map PDF, for House bills and for the Senate
-- bills the House acted on (SenateActList). One row per text version.
select
    b.session_code,
    b.bill,
    c.text_index,
    c.document_name,
    c.web_name,
    c.lr_number,
    c.version_type_code,
    c.version_sort,
    c.text_link as text_url,
    c.map_link as map_url
from {{ source('mo_house', 'xml_bill_texts') }} as c
inner join {{ source('mo_house', 'xml_bills') }} as b
    on c.session_code = b.session_code and c.file_name = b.file_name
where (c.text_link is not null or c.map_link is not null)

union all

select
    session_code,
    bill,
    text_index,
    document_name,
    web_name,
    lr_number,
    version_type_code,
    version_sort,
    text_link as text_url,
    map_link as map_url
from {{ source('mo_house', 'xml_senate_act_texts') }}
where (text_link is not null or map_link is not null)
