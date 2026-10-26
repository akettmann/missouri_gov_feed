-- House committee and subcommittee memberships per person and session, with the member's position
-- (Chair, Vice-Chair, Co-Chair, Ranking Minority Member, Member). End-of-session snapshot from the House member
-- pages, with the COMMITTEELIST export for session 253, whose member pages carry none. Former members are kept
-- (official_id is the person id from int_mo_house__member_identity; is_current_official says whether the person
-- is in dim_official). source_url is the House file the row was read from. Grain: one row per
-- (person, session, committee).
select
    m.person_key as official_id,
    m.session_code,
    m.session_year,
    m.committee_name,
    m.position_name,
    m.is_subcommittee,
    m.source,
    m.source_url,
    o.official_id is not null as is_current_official
from {{ ref('int_mo_house__committee_memberships') }} as m
left join {{ ref('dim_official') }} as o on m.person_key = o.official_id
