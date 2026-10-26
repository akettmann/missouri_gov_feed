-- Members of each House committee per session from the House COMMITTEELIST export: one row per (session,
-- committee, member). Held only for sessions 231, 241, 251, 253 and 254 (2023 onward). The member is
-- identified by the House district number, which is unique within a session.
select
    c.session_code,
    2000 + {{ dbt.safe_cast('left(c.session_code, 2)', dbt.type_int()) }} as session_year,
    c.committee_id,
    trim(c.name) as committee_name,
    m.member_name,
    {{ dbt.safe_cast('m.member_district', dbt.type_int()) }} as district_number,
    trim(m.position_name) as position_name,
    m.chamber
from {{ source('mo_house', 'xml_committees') }} as c
inner join {{ source('mo_house', 'xml_committee_members') }} as m
    on c.session_code = m.session_code and c.file_name = m.file_name and c.committee_id = m.committee_id
