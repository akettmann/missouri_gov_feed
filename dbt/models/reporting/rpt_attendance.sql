-- How often each official was present for recorded votes, per chamber and session, next to the whole
-- chamber's rate for the same session (every member, from int_votes__member_votes). Present means any
-- recorded position: yea, nay or present. Absences are split, since "absent with leave" is an excused
-- absence in the MO Senate journals and "recused" (Senate Rule 91, a member on the floor) is neither.
-- Sessions: MO House session codes (year + type, e.g. 251 = 2025 regular),
-- MO Senate journal years, Congress numbers.
with official as (
    select
        official_id,
        full_name,
        chamber,
        session_code,
        count(*) as votes_recorded,
        sum(case when vote_cast in ('yea', 'nay', 'present') then 1 else 0 end) as votes_present,
        sum(case when vote_cast = 'absent' then 1 else 0 end) as absent,
        sum(case when vote_cast = 'absent with leave' then 1 else 0 end) as absent_with_leave,
        sum(case when vote_cast = 'not voting' then 1 else 0 end) as not_voting,
        sum(case when vote_cast = 'recused' then 1 else 0 end) as recused_from_voting,
        min(vote_date) as first_vote_date,
        max(vote_date) as last_vote_date
    from {{ ref('fct_votes') }}
    group by official_id, full_name, chamber, session_code
),

chamber as (
    select
        chamber,
        session_code,
        count(*) as chamber_votes_recorded,
        sum(case when vote_cast in ('yea', 'nay', 'present') then 1 else 0 end) as chamber_votes_present
    from {{ ref('int_votes__member_votes') }}
    group by chamber, session_code
)

select
    o.official_id,
    o.full_name,
    o.chamber,
    o.session_code,
    o.first_vote_date,
    o.last_vote_date,
    o.votes_recorded,
    o.votes_present,
    o.absent,
    o.absent_with_leave,
    o.not_voting,
    o.recused_from_voting,
    round(100.0 * o.votes_present / o.votes_recorded, 1) as attendance_pct,
    round(100.0 * c.chamber_votes_present / c.chamber_votes_recorded, 1) as chamber_attendance_pct
from official as o
left join chamber as c on o.chamber = c.chamber and o.session_code = c.session_code
