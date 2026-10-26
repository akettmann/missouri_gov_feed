-- Witness-form PDF links per bill (committee testimony), for House bills and for the Senate bills the House acted
-- on (SenateActList). Links only: the forms name citizens and are neither fetched nor parsed. Empty <Witness/>
-- elements (no link) are dropped.
select
    b.session_code,
    b.bill,
    c.witness_index,
    c.witness_forms_link as witness_forms_url,
    c.witness_form_link_description as description
from {{ source('mo_house', 'xml_bill_witnesses') }} as c
inner join {{ source('mo_house', 'xml_bills') }} as b
    on c.session_code = b.session_code and c.file_name = b.file_name
where c.witness_forms_link is not null

union all

select
    session_code,
    bill,
    witness_index,
    witness_forms_link as witness_forms_url,
    witness_form_link_description as description
from {{ source('mo_house', 'xml_senate_act_witnesses') }}
where witness_forms_link is not null
