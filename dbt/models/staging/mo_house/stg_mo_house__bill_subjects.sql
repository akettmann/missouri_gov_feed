-- The House's subject index terms for each bill ("APPROPRIATIONS", "EDUCATION, ELEMENTARY AND SECONDARY").
-- The XML export has them from the 2024 sessions on; earlier sessions have none.
select
    b.session_code,
    b.bill,
    s.subject_id,
    s.subject_name
from {{ source('mo_house', 'xml_bills') }} as b
inner join {{ source('mo_house', 'xml_bill_subjects') }} as s
    on b.session_code = s.session_code and b.file_name = s.file_name
