-- Committee and subcommittee posts of each MO House member per session, as the member's own XML page lists
-- them (end-of-session snapshot): committee name and position (Chair, Vice-Chair, Co-Chair, Ranking Minority
-- Member, Member). Subcommittees carry "Subcommittee" in the name. The export has none for session 253.
with src as (
    select
        {{ mogov.json_str('payload', '$.session_code') }} as session_code,
        {{ mogov.json_fragment('payload', '$.doc.RepresentativeData[0].RepresentativeInfo[0]') }} as info
    from {{ source('mo_house', 'members') }}
)

select
    s.session_code,
    2000 + {{ dbt.safe_cast('left(s.session_code, 2)', dbt.type_int()) }} as session_year,
    {{ mogov.regex_extract(mogov.json_str('s.info', '$.PhotoLink[0]'), 'id=([0-9]+)') }} as house_member_id,
    trim({{ mogov.json_str('c.value', '$.CommitteeName[0]') }}) as committee_name,
    trim({{ mogov.json_str('c.value', '$.CommitteePosition[0]') }}) as position_name
from src as s
cross join lateral {{ mogov.json_elements('s.info', '$.Committees[0].Committee') }} as c
where {{ mogov.json_str('c.value', '$.CommitteeName[0]') }} is not null
