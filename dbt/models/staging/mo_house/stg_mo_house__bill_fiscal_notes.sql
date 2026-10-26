-- Fiscal note PDF links per bill, for House bills and for the Senate bills the House acted on (SenateActList).
-- The XML names the element FiscalNote or FiscalNotes; the link is what matters.
select
    b.session_code,
    b.bill,
    c.fiscal_note_index,
    c.fiscal_note_link as fiscal_note_url
from {{ source('mo_house', 'xml_bill_fiscal_notes') }} as c
inner join {{ source('mo_house', 'xml_bills') }} as b
    on c.session_code = b.session_code and c.file_name = b.file_name
where c.fiscal_note_link is not null

union all

select
    session_code,
    bill,
    fiscal_note_index,
    fiscal_note_link as fiscal_note_url
from {{ source('mo_house', 'xml_senate_act_fiscal_notes') }}
where fiscal_note_link is not null
