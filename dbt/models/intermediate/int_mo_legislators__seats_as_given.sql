-- Every Missouri legislative seat-term in Open States (current and retired people), keyed for matching:
-- chamber, district number, surname key, and date range (open-ended where Open States has no date), plus
-- person_id, the stable id of the person holding the seat (int_officials__person_ids). openstates_id stays the id
-- Open States gave the term; use person_id wherever a seat holder becomes an official.
-- Rows and corrections are those of int_mo_legislators__seat_terms. The dates are still Open States' own: the
-- Senate terms are re-dated from the journal roll calls in int_mo_legislators__seats, which is what to use. This
-- model exists so int_mo_senate__votes can attribute votes to senators without depending on the dates those votes
-- later correct. start_quality is int_mo_legislators__seat_terms' flag (dated, undated or placeholder), carried so the
-- re-dating in int_mo_legislators__seats reads it instead of the 1900-01-01 start.
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
    t.start_quality,
    coalesce(x.person_id, t.openstates_id) as person_id
from {{ ref('int_mo_legislators__seat_terms') }} as t
left join {{ ref('int_officials__person_ids') }} as x on t.openstates_id = x.alias_id
