-- Sanity check (#660, #227): legislature payroll is matched only to an official who held that chamber that year.
-- Every fct_salaries row from the LEGISLATURE agency (chamber from position_title: STATE REPRESENTATIVE* is the
-- House, the rest the Senate) must have its official in int_officeholders__years for that chamber and calendar
-- year, or be a final check: a small payment (under half the year's top legislature pay in that chamber, all
-- payees counted; int_mo_legislators__final_checks uses the same half, per title) to an official whose seat in that
-- chamber (int_mo_legislators__seats) ended the December before or that January. The seat end, not
-- int_mo_legislators__final_checks, is the test, because fct_salaries also pairs a final check by seat when the
-- payroll's legal first name does not fit, or when the member returns to the chamber later, and
-- int_mo_legislators__final_checks leaves both out. It also covers
-- 2017 final checks for seats that ended 2016-12-31, before the first roster year (Hough, Hoskins, Webber).
-- Guards the #227 failure: David Smith's profile showing Cody Smith's 2017-2020 pay, full salaries from years
-- before his own seat began. No floor: any row is a failure.
-- Measured on a full build (2026-10): 0 failing of 824 LEGISLATURE rows; 26 pass only as final checks, $1,496 to
-- $2,359 (at most 6.1% of the chamber's top pay): 2017 Hoskins, Hough, Webber; 2019 to 2025 departures and moves.
-- int_mo_legislators__final_checks lists only 20 of the 26: Moon, Rusty Black, Henderson and Nurrenbern (legal
-- first name does not fit), Matthiesen and Simmons (back in the House later).

-- the chamber, not the title: a title can have one payee in a year (2017 STATE REPRESENTATIVE-LEADERSHP: only
-- Denny Hoskins' final check), and then its top pay is that final check
with top_pay as (
    select
        p.calendar_year,
        case when p.position_title like 'STATE REPRESENTATIVE%' then 'lower' else 'upper' end as seat_chamber,
        max(p.gross_pay) as top_pay
    from {{ ref('stg_mo_employee_pay__pay') }} as p
    inner join {{ ref('mo_payroll_office_titles') }} as t
        on p.agency_name = t.agency_name and p.position_title = t.position_title
    where t.office_group = 'legislature'
    group by p.calendar_year, case when p.position_title like 'STATE REPRESENTATIVE%' then 'lower' else 'upper' end
),

pay as (
    select
        s.official_id,
        s.calendar_year,
        s.position_title,
        s.employee_name,
        s.pay,
        tp.top_pay,
        case when s.position_title like 'STATE REPRESENTATIVE%' then 'state_house' else 'state_senate' end as office,
        case when s.position_title like 'STATE REPRESENTATIVE%' then 'lower' else 'upper' end as seat_chamber
    from {{ ref('fct_salaries') }} as s
    left join top_pay as tp
        on
            s.calendar_year = tp.calendar_year
            and tp.seat_chamber = case when s.position_title like 'STATE REPRESENTATIVE%' then 'lower' else 'upper' end
    where s.agency_name = 'LEGISLATURE'
),

held as (
    select distinct
        official_id,
        office,
        year
    from {{ ref('int_officeholders__years') }}
    where office in ('state_house', 'state_senate')
),

-- the pay year after each seat ended: the following year for a December end, the same year for a January end
-- (Open States ends the 2020, 2022 and 2024 departures on 2021-01-06, 2023-01-03 and 2025-01-07/08)
seat_ends as (
    select distinct
        person_id,
        chamber,
        case
            when extract(month from end_date) = 12 then extract(year from end_date) + 1
            else extract(year from end_date)
        end as final_check_year
    from {{ ref('int_mo_legislators__seats') }}
    where extract(month from end_date) in (1, 12)
)

select
    p.official_id,
    p.calendar_year,
    p.office,
    p.position_title,
    p.employee_name,
    p.pay,
    p.top_pay
from pay as p
left join held as h
    on p.official_id = h.official_id and p.office = h.office and p.calendar_year = h.year
left join seat_ends as e
    on
        p.official_id = e.person_id
        and p.seat_chamber = e.chamber
        and p.calendar_year = e.final_check_year
        and p.pay * 2 < p.top_pay
where h.official_id is null and e.person_id is null
