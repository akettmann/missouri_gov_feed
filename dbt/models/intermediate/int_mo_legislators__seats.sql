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
-- The last two rules need the journals to cover the term: with no journal loaded, or a calendar year inside the term
-- (from the journals' first date to the term's end; to the journals' last date for an open term) with no journal vote
-- at all, which includes years after the journals stop, a term is left as Open States gives it, never dropped or
-- capped for lacking votes (#534). Only the first rule (an undated start) needs a vote of the term itself.
with as_given as (
    select * from {{ ref('int_mo_legislators__seats_as_given') }}
),

-- With no journal loaded (a fresh or partial environment) first_date is the open-end date, so no term runs "into
-- the journal years" and none is dropped or capped; the min/max are null on an empty table.
journal as (
    select
        coalesce(min(vote_date), {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as first_date,
        coalesce(max(vote_date), {{ dbt.safe_cast("'1900-01-01'", 'date') }}) as last_date
    from {{ ref('int_mo_senate__votes') }}
),

journal_years as (
    select distinct extract(year from vote_date) as yr
    from {{ ref('int_mo_senate__votes') }}
),

-- calendar years of a term that the journals could cover (the term's years from the first journal date to the last
-- journal date) against the years in which the journal has votes at all. A term is only dropped or capped for lacking
-- votes when every one of those years has journal votes; a missing year (a partial raw load) leaves it as given.
term_years as (
    select
        s.openstates_id,
        s.district_number,
        s.start_date,
        s.end_date,
        extract(year from case when s.start_date > j.first_date then s.start_date else j.first_date end) as year_from,
        -- a closed term counts to its own end, so years after the journal's last date (a journal that stops early)
        -- have no votes and leave the term as given; only an open term stops at the journal's last date
        extract(
            year from case
                when s.end_date < {{ dbt.safe_cast("'9999-12-31'", 'date') }} then s.end_date
                else j.last_date
            end
        ) as year_to
    from as_given as s
    cross join journal as j
    where s.chamber = 'upper'
),

term_coverage as (
    select
        t.openstates_id,
        t.district_number,
        t.start_date,
        t.end_date,
        count(y.yr) >= max(t.year_to - t.year_from + 1) as journal_covers_term
    from term_years as t
    left join journal_years as y on y.yr between t.year_from and t.year_to
    group by t.openstates_id, t.district_number, t.start_date, t.end_date
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
            and c.journal_covers_term
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
                and c.journal_covers_term
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
    left join term_coverage as c
        on
            s.openstates_id = c.openstates_id
            and s.district_number = c.district_number
            and s.start_date = c.start_date
            and s.end_date = c.end_date
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
