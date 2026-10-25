-- Seat-matched key for each MO House member per session (House XML is authoritative for the House roster).
-- raw_person_key = Open States id when the seat (district + date + surname) matches one person, otherwise
-- mohouse:<House member id>, so people missing from Open States still get a key. One person can end up with
-- several raw keys across sessions (see int_officials__person_ids); int_mo_house__member_identity applies that.
with members as (
    select
        *,
        {{ mogov.name_key('last_name') }} as surname_key,
        {{ dbt.safe_cast(dbt.concat(['session_year', "'-03-01'"]), 'date') }} as session_date
    from {{ ref('stg_mo_house__members') }}
),

seat_match as (
    select
        m.session_code,
        m.district_number,
        max(s.openstates_id) as openstates_id
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
    group by 1, 2
    having count(distinct s.openstates_id) = 1
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
