-- Every Missouri legislative seat-term in Open States (current and retired people), keyed for matching:
-- chamber, district number, surname key, and date range (open-ended where Open States has no date), plus
-- person_id, the stable id of the person holding the seat (int_officials__person_ids). openstates_id stays the id
-- Open States gave the term; use person_id wherever a seat holder becomes an official.
-- Rows and corrections are those of int_mo_legislators__seat_terms. Grain: one row per Open States legislative
-- seat-term.
select
    t.openstates_id,
    t.full_name,
    t.family_name,
    t.party,
    t.surname_key,
    t.full_name_key,
    t.chamber,
    t.district_number,
    t.start_date,
    t.end_date,
    coalesce(x.person_id, t.openstates_id) as person_id
from {{ ref('int_mo_legislators__seat_terms') }} as t
left join {{ ref('int_officials__person_ids') }} as x on t.openstates_id = x.alias_id
