-- Committee and subcommittee posts of each MO House member per session, as the member's own XML page lists
-- them (end-of-session snapshot): committee name and position (Chair, Vice-Chair, Co-Chair, Ranking Minority
-- Member, Member). Subcommittees carry "Subcommittee" in the name. The export has none for session 253.
select
    m.session_code,
    2000 + {{ dbt.safe_cast('left(m.session_code, 2)', dbt.type_int()) }} as session_year,
    {{ mogov.regex_extract('m.photo_link', 'id=([0-9]+)') }} as house_member_id,
    trim(c.committee_name) as committee_name,
    trim(c.committee_position) as position_name
from {{ source('mo_house', 'xml_members') }} as m
inner join {{ source('mo_house', 'xml_member_committees') }} as c
    on m.session_code = c.session_code and m.file_name = c.file_name
where c.committee_name is not null
