-- House committee and subcommittee memberships per official and session, with the member's position
-- (Chair, Vice-Chair, Co-Chair, Ranking Minority Member, Member). End-of-session snapshot from the House member
-- pages, with the COMMITTEELIST export for session 253, whose member pages carry none. Officials not in
-- dim_official (former members) are left out. Grain: one row per (official, session, committee).
select
    m.person_key as official_id,
    m.session_code,
    m.session_year,
    m.committee_name,
    m.position_name,
    m.is_subcommittee,
    m.source
from {{ ref('int_mo_house__committee_memberships') }} as m
inner join {{ ref('dim_official') }} as o on m.person_key = o.official_id
