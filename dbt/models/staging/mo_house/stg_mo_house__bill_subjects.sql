-- The House's subject index terms for each bill ("APPROPRIATIONS", "EDUCATION, ELEMENTARY AND SECONDARY").
-- The XML export has them from the 2024 sessions on; earlier sessions have none.
select
    b.session_code,
    b.bill,
    {{ mogov.json_str('s.value', '$.SubjectID[0]') }} as subject_id,
    {{ mogov.json_str('s.value', '$.SubjectName[0]') }} as subject_name
from {{ ref('stg_mo_house__bills') }} as b
cross join lateral {{ mogov.json_elements('b.bill_doc', '$.SubjectIndex') }} as s
