-- Identity for each MO House member per session (House XML is authoritative for the House roster).
-- person_key = the stable person id (int_officials__person_ids) of the key the seat match gave: an Open States id
-- when the seat (district + date + surname) matches one person, otherwise mohouse:<House member id>, so people
-- missing from Open States still get a key and a person split across several keys gets one. raw_person_key is the
-- key before that.
select
    k.session_code,
    k.session_year,
    k.district,
    k.district_number,
    k.house_member_id,
    k.first_name,
    k.last_name,
    k.surname_key,
    k.full_name,
    k.party,
    k.hometown,
    k.year_elected,
    k.biography,
    k.openstates_id,
    k.raw_person_key,
    coalesce(x.person_id, k.raw_person_key) as person_key
from {{ ref('int_mo_house__member_seat_keys') }} as k
left join {{ ref('int_officials__person_ids') }} as x on k.raw_person_key = x.alias_id
