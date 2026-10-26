-- Members of each House committee per session from the House COMMITTEELIST export: one row per (session,
-- committee, member). Held only for sessions 231, 241, 251, 253 and 254 (2023 onward). The member is
-- identified by the House district number, which is unique within a session.
with src as (
    select
        {{ mogov.json_str('payload', '$.session_code') }} as session_code,
        {{ mogov.json_fragment('payload', '$.doc') }} as doc
    from {{ source('mo_house', 'lists') }}
    where {{ mogov.json_str('payload', '$.list') }} = 'COMMITTEELIST'
)

select
    s.session_code,
    2000 + {{ dbt.safe_cast('left(s.session_code, 2)', dbt.type_int()) }} as session_year,
    {{ mogov.json_str('c.value', '$.ID[0]') }} as committee_id,
    trim({{ mogov.json_str('c.value', '$.Name[0]') }}) as committee_name,
    {{ mogov.json_str('m.value', '$.MemberName[0]') }} as member_name,
    {{ dbt.safe_cast(mogov.json_str('m.value', '$.MemberDistrict[0]'), dbt.type_int()) }} as district_number,
    trim({{ mogov.json_str('m.value', '$.PositionName[0]') }}) as position_name,
    {{ mogov.json_str('m.value', '$.Chamber[0]') }} as chamber
from src as s
cross join lateral {{ mogov.json_elements('s.doc', '$.Committee') }} as c
cross join lateral {{ mogov.json_elements('c.value', '$.CommitteeMembers[0].CommitteeMember') }} as m
