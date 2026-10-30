-- Sanity check on fct_votes.vote_stage (#804): the rules should recognise nearly every Missouri roll call. On the
-- 2026-10-27 build `unknown` was 0.6% of House roll calls (37 of 6,022) and 4.6% of Senate ones (104 of 2,261), at
-- most 11% in any chamber and year. The Senate is higher because 100 of its 104 are journal page headers or vote-list
-- fragments that run into the sentence that introduces a vote (the other 4 are listed in #816). Bounds: House 2%,
-- Senate 8% overall; 20% in any chamber and year
-- with at least 50 roll calls (a year all `unknown` means the House calendar or Senate wording changed). Also every
-- chamber and year with roll calls needs at least one third-reading vote. Returns the chambers / years out of bounds.
with votes as (
    select distinct
        chamber,
        vote_id,
        extract(year from vote_date) as vote_year,
        vote_stage
    from {{ ref('fct_votes') }}
    where chamber in ('state_house', 'state_senate')
),

by_year as (
    select
        chamber,
        vote_year,
        count(*) as roll_calls,
        sum(case when vote_stage = 'unknown' then 1 else 0 end) as unknown_calls,
        sum(case when vote_stage = 'third_reading' then 1 else 0 end) as third_reading_calls
    from votes
    group by chamber, vote_year
),

by_chamber as (
    select
        chamber,
        cast(null as integer) as vote_year,
        sum(roll_calls) as roll_calls,
        sum(unknown_calls) as unknown_calls,
        sum(third_reading_calls) as third_reading_calls
    from by_year
    group by chamber
)

select
    chamber,
    vote_year,
    roll_calls,
    unknown_calls,
    third_reading_calls
from by_year
where
    (roll_calls >= 50 and unknown_calls * 1.0 / roll_calls > 0.20)
    or third_reading_calls = 0

union all

select
    chamber,
    vote_year,
    roll_calls,
    unknown_calls,
    third_reading_calls
from by_chamber
where
    unknown_calls * 1.0 / roll_calls > case chamber when 'state_house' then 0.02 else 0.08 end
