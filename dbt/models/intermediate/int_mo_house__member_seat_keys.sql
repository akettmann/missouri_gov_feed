-- Seat-matched key for each MO House member per session (House XML is authoritative for the House roster).
-- raw_person_key = Open States id when the seat (district + date + surname) matches one person (or, among several
-- same-surname terms, one whose name also starts with the member's given name), otherwise
-- mohouse:<House member id>, so people missing from Open States still get a key. One person can end up with
-- several raw keys across sessions (see int_officials__person_ids); int_mo_house__member_identity applies that.
with members as (
    select
        *,
        {{ mogov.name_key('last_name') }} as surname_key,
        {{ mogov.name_key('first_name') }} as first_name_key,
        {{ dbt.safe_cast(dbt.concat(['session_year', "'-03-01'"]), 'date') }} as session_date
    from {{ ref('stg_mo_house__members') }}
),

candidates as (
    select
        m.session_code,
        m.district_number,
        s.openstates_id,
        -- the Open States name starts with the House member's given name ("joe don mcgaugh" for "Joe Don")
        case when s.full_name_key like m.first_name_key || ' %' then 1 else 0 end as given_name_match
    from members as m
    inner join {{ ref('int_mo_legislators__seat_terms') }} as s
        on
            s.chamber = 'lower'
            and m.district_number = s.district_number
            and m.session_date between s.start_date and s.end_date
            and (
                m.surname_key = s.surname_key
                or m.surname_key like '%' || s.surname_key
                or s.full_name_key like '%' || m.surname_key
            )
),

-- one Open States person matches the seat, or (same-surname terms overlapping, e.g. a relative whose term has no
-- start date) exactly one of them also matches the given name; otherwise no match
-- Grouped by (session, district), not by member: a seat with two House members in one session (a mid-session
-- replacement) could hand one member's id to the other. The roster is an end-of-session snapshot so none exist today;
-- a unique test on (session_code, district_number) fails if that changes (#475).
seat_match as (
    select
        session_code,
        district_number,
        case
            when count(distinct openstates_id) = 1 then max(openstates_id)
            else max(case when given_name_match = 1 then openstates_id end)
        end as openstates_id
    from candidates
    group by 1, 2
    having
        count(distinct openstates_id) = 1
        or count(distinct case when given_name_match = 1 then openstates_id end) = 1
),

seat_names as (
    select distinct
        openstates_id,
        full_name_key
    from {{ ref('int_mo_legislators__seat_terms') }}
),

-- the House lists a departed member in a later session's roster (Rebecca Roeber, HD34, is still listed in 2020
-- though her term ended in 2019 and the seat was vacant until Rick Roeber, #152), so the seat match lands on the
-- successor. A member id whose other sessions matched exactly one Open States person by given name keeps that person
-- where the seat match found someone else (that match cannot also carry the given name: it would be a second anchor).
name_anchors as (
    select
        m.house_member_id,
        max(sm.openstates_id) as openstates_id
    from members as m
    inner join seat_match as sm on m.session_code = sm.session_code and m.district_number = sm.district_number
    inner join seat_names as n on sm.openstates_id = n.openstates_id
    where n.full_name_key like m.first_name_key || ' %'
    group by 1
    having count(distinct sm.openstates_id) = 1
),

resolved as (
    select
        m.session_code,
        m.house_member_id,
        case
            when
                sm.openstates_id is not null
                and a.openstates_id is not null
                and sm.openstates_id != a.openstates_id
                then a.openstates_id
            else sm.openstates_id
        end as openstates_id
    from members as m
    left join seat_match as sm on m.session_code = sm.session_code and m.district_number = sm.district_number
    left join name_anchors as a on m.house_member_id = a.house_member_id
)

select
    m.session_code,
    m.session_year,
    m.district,
    m.district_number,
    m.house_member_id,
    m.first_name,
    m.last_name,
    m.surname_key,
    trim(m.first_name || ' ' || m.last_name) as full_name,
    m.party,
    m.hometown,
    m.year_elected,
    m.biography,
    r.openstates_id,
    coalesce(r.openstates_id, 'mohouse:' || m.house_member_id) as raw_person_key
from members as m
left join resolved as r on m.session_code = r.session_code and m.house_member_id = r.house_member_id
