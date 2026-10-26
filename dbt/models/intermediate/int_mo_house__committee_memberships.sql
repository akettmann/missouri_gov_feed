-- House committee and subcommittee memberships per member and session, keyed to the person (person_key from
-- int_mo_house__member_identity). The member pages (stg_mo_house__member_committees) cover every session but
-- 253; for a session with no member-page rows the COMMITTEELIST export fills in (House members only, matched
-- on session + district). Grain: one row per (session, member, committee).
with member_pages as (
    select
        c.session_code,
        i.person_key,
        c.committee_name,
        c.position_name,
        'member_page' as source
    from {{ ref('stg_mo_house__member_committees') }} as c
    inner join {{ ref('int_mo_house__member_identity') }} as i
        on c.session_code = i.session_code and c.house_member_id = i.house_member_id
),

list_rows as (
    select
        l.session_code,
        i.person_key,
        l.committee_name,
        l.position_name,
        'committee_list' as source
    from {{ ref('stg_mo_house__committee_list_members') }} as l
    inner join {{ ref('int_mo_house__member_identity') }} as i
        on l.session_code = i.session_code and l.district_number = i.district_number
    where
        l.chamber = 'H'
        and l.session_code not in (select distinct m.session_code from member_pages as m)
),

unioned as (
    select * from member_pages
    union all
    select * from list_rows
)

select
    session_code,
    2000 + {{ dbt.safe_cast('left(session_code, 2)', dbt.type_int()) }} as session_year,
    person_key,
    committee_name,
    position_name,
    source,
    committee_name like '%Subcommittee%' as is_subcommittee
from unioned
