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
    sm.openstates_id,
    coalesce(sm.openstates_id, 'mohouse:' || m.house_member_id) as raw_person_key
from members as m
left join seat_match as sm on m.session_code = sm.session_code and m.district_number = sm.district_number
