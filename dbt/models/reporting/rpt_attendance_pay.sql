-- Dollars paid per vote attended, next to the attendance stats (rpt_attendance). Pay is per calendar year
-- (fct_salaries), so the votes are counted per calendar year of the vote date too, and the two always cover
-- the same period. Sessions that share a year (a regular and an extraordinary House session) fall into one
-- year row, and a Congress or any session that crosses New Year is split by the date of each vote.
--   attended = yea, nay or present (the same numerator as attendance_pct). A recusal (MO Senate Rule 91,
--   #135 is undecided) is not attended, so it is left out of the denominator's votes_attended.
--   pay      = the sum of the official's pay rows for the year in the chamber's own positions (state payroll
--   gross pay; statutory salary for Congress), so a year with two positions in one chamber is summed. Pay is
--   matched to the chamber by position title, so a representative who became a senator mid-year has a pay
--   row and a vote count in each chamber, and neither pays for the other's votes.
--   The statutory salary of the year still in progress is not counted (see pay_by_year).
-- Two kinds of row, told apart by period: one per calendar year ('2021'), and one per official and chamber
-- over the years where pay and votes both exist ('covered years'). A year with votes but no pay row (the
-- payroll starts in 2017) has a null pay and stays out of the total, which says how many of the years it
-- covers (covered_years of voting_years). Zero attended votes in the covered years gives a null figure, not
-- infinity.
with votes as (
    select
        official_id,
        chamber,
        extract(year from vote_date) as calendar_year,
        count(*) as votes_recorded,
        sum(case when vote_cast in ('yea', 'nay', 'present') then 1 else 0 end) as votes_attended
    from {{ ref('fct_votes') }}
    group by official_id, chamber, extract(year from vote_date)
),

pay as (
    select
        official_id,
        calendar_year,
        case
            when position_title like 'STATE REPRESENTATIVE%' then 'state_house'
            when position_title = 'U.S. REPRESENTATIVE' then 'us_house'
            when position_title = 'U.S. SENATOR' then 'us_senate'
            when agency_name = 'LEGISLATURE' then 'state_senate'
        end as chamber,
        pay_basis,
        pay
    from {{ ref('fct_salaries') }}
),

pay_by_year as (
    select
        official_id,
        chamber,
        calendar_year,
        sum(pay) as pay_amount,
        min(pay_basis) as pay_basis
    from pay
    where
        chamber is not null
        -- a statutory salary is an annual rate, so the year in progress would pay a full year against
        -- a part year of votes; it is left out until the year ends. State payroll rows are what was paid.
        and not (pay_basis = 'statutory salary' and calendar_year >= extract(year from current_date))
    group by official_id, chamber, calendar_year
),

yearly as (
    select
        v.official_id,
        v.chamber,
        v.calendar_year,
        v.votes_recorded,
        v.votes_attended,
        p.pay_amount,
        p.pay_basis
    from votes as v
    left join pay_by_year as p
        on
            v.official_id = p.official_id
            and v.chamber = p.chamber
            and v.calendar_year = p.calendar_year
),

year_rows as (
    select
        official_id,
        chamber,
        cast(calendar_year as varchar) as period,
        calendar_year,
        1 as voting_years,
        case when pay_amount is null then 0 else 1 end as covered_years,
        votes_recorded,
        votes_attended,
        pay_amount,
        pay_basis
    from yearly
),

total_rows as (
    select
        official_id,
        chamber,
        'covered years' as period,
        cast(null as integer) as calendar_year,
        count(*) as voting_years,
        sum(case when pay_amount is null then 0 else 1 end) as covered_years,
        sum(case when pay_amount is null then 0 else votes_recorded end) as votes_recorded,
        sum(case when pay_amount is null then 0 else votes_attended end) as votes_attended,
        sum(pay_amount) as pay_amount,
        min(pay_basis) as pay_basis
    from yearly
    group by official_id, chamber
    having sum(case when pay_amount is null then 0 else 1 end) > 0
),

combined as (
    select * from year_rows
    union all
    select * from total_rows
)

select
    official_id,
    chamber,
    period,
    calendar_year,
    voting_years,
    covered_years,
    votes_recorded,
    votes_attended,
    pay_amount,
    pay_basis,
    case
        when pay_amount is null or votes_attended = 0 then null
        else round(pay_amount / votes_attended, 2)
    end as dollars_per_vote_attended
from combined
