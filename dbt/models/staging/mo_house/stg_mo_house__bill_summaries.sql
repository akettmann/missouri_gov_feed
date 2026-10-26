-- Bill summary PDFs: one row per summary link per bill version (introduced, committee substitute, ...), for House bills
-- and for the Senate bills the House acted on (SenateActList). Rows without a link are dropped.
select
    b.session_code,
    b.bill,
    c.summary_index,
    c.document_name,
    c.summary_text_link as summary_url,
    c.version_type_code,
    c.lr_number,
    c.version_sort
from {{ source('mo_house', 'xml_bill_summaries') }} as c
inner join {{ source('mo_house', 'xml_bills') }} as b
    on c.session_code = b.session_code and c.file_name = b.file_name
where c.summary_text_link is not null

union all

select
    session_code,
    bill,
    summary_index,
    document_name,
    summary_text_link as summary_url,
    version_type_code,
    lr_number,
    version_sort
from {{ source('mo_house', 'xml_senate_act_summaries') }}
where summary_text_link is not null
