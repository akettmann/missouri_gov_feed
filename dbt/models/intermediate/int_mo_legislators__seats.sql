-- Every Missouri legislative seat-term in Open States (current and retired people), keyed for matching:
-- chamber, district number, surname key, and date range (open-ended where Open States has no date), plus
-- person_id, the stable id of the person holding the seat (int_officials__person_ids). openstates_id stays the id
-- Open States gave the term; use person_id wherever a seat holder becomes an official.
-- Rows and corrections are those of int_mo_legislators__seat_terms (via int_mo_legislators__seats_as_given). House
-- terms keep Open States' dates. Senate terms are dated from the journal roll calls where Open States cannot
-- (#516, #522), term by term: the votes int_mo_senate__votes attributes to a term are the ones cast by its person
-- within the term's Open States dates. Open States has no start date for 25 senators in office from 2017, and a
-- few terms end long after the person left (Joseph Keaveny, 2011-2018, never voted in the journals, which begin
-- 2017-01-04; Ryan Silvey's last vote was 2017-09-13, not 2018-12-31):
--   * an undated start (1900-01-01) becomes the term's first roll-call vote. That is the latest the start can be (a
--     senator seated on the journal's first day, 2017-01-04, started on or before it), so it decides which years
--     the senator held the seat in without inventing a start. It agrees with every dated start (the first vote
--     falls on or just after it). A term that ended before the journals begin keeps Open States' dates.
--   * a closed term that Open States ends more than a year after the term's last roll-call vote ends at that vote.
--     A smaller gap stays: a senator who resigned on January 16 voted last on January 13 (Jason Holsman, 2020), and
--     the Open States date, not the last vote, says whether they held the seat past the January 15 handover. An
--     open term (no end date) is never cut.
--   * a closed term that runs into the journal years with no vote at all was not held in them. Where it started
--     before the journals began, it ends the day before the first journal date (the latest it can have ended);
--     otherwise (an undated start, or a start inside the journal years) the term is dropped.
with as_given as (
    select * from {{ ref('int_mo_legislators__seats_as_given') }}
),

journal as (
    select
        min(vote_date) as first_date,
        max(vote_date) as last_date
    from {{ ref('int_mo_senate__votes') }}
),

term_votes as (
    select
        s.openstates_id,
        s.district_number,
        s.start_date,
        s.end_date,
        min(v.vote_date) as first_vote,
        max(v.vote_date) as last_vote
    from as_given as s
    inner join {{ ref('int_mo_senate__votes') }} as v
        on s.person_id = v.person_key and v.vote_date between s.start_date and s.end_date
    where s.chamber = 'upper'
    group by s.openstates_id, s.district_number, s.start_date, s.end_date
),

dated as (
    select
        s.openstates_id,
        s.full_name,
        s.family_name,
        s.party,
        s.surname_key,
        s.full_name_key,
        s.chamber,
        s.district_number,
        s.person_id,
        s.start_date as given_start,
        s.end_date as given_end,
        j.first_date,
        -- a closed Senate term in the journal years with no vote at all
        (
            s.chamber = 'upper'
            and v.openstates_id is null
            and s.end_date < {{ dbt.safe_cast("'9999-12-31'", 'date') }}
            and s.end_date >= j.first_date
        ) as is_unvoted,
        case
            when
                s.chamber = 'upper'
                and s.start_date <= {{ dbt.safe_cast("'1900-01-01'", 'date') }}
                and v.first_vote is not null
                then v.first_vote
            else s.start_date
        end as start_date,
        case
            when
                s.chamber = 'upper'
                and s.end_date < {{ dbt.safe_cast("'9999-12-31'", 'date') }}
                and {{ dbt.dateadd('year', 1, 'v.last_vote') }} < s.end_date
                then v.last_vote
            else s.end_date
        end as end_date
    from as_given as s
    cross join journal as j
    left join term_votes as v
        on
            s.openstates_id = v.openstates_id
            and s.district_number = v.district_number
            and s.start_date = v.start_date
            and s.end_date = v.end_date
)

select
    openstates_id,
    full_name,
    family_name,
    party,
    surname_key,
    full_name_key,
    chamber,
    district_number,
    start_date,
    case
        when is_unvoted then {{ dbt.dateadd('day', -1, 'first_date') }}
        else end_date
    end as end_date,
    person_id
from dated
where
    -- an unvoted term with a dated start before the journals ends the day before them; any other is dropped
    not is_unvoted
    or (given_start > {{ dbt.safe_cast("'1900-01-01'", 'date') }} and given_start < first_date)
