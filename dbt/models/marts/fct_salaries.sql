-- Pay received by current state officials as officeholders, per calendar year, from the state payroll
-- (data.mo.gov State Employee Pay, 2017+). Gross pay is all pay received in the year, not the base salary;
-- a year with a change of office has a row per position. Only officeholder titles count
-- (seed mo_payroll_office_titles), never staff positions.
-- The payroll prints legal names ("LUETKEMEYER, ANTON H" for Tony Luetkemeyer, "BLACK, JAMES R" for Rusty
-- Black), so legislators are matched by seat instead of first name:
--   legislature  surname + chamber + year against every legislator's seats (int_mo_legislators__seats),
--                kept only when exactly one member of that chamber that year has the surname and exactly
--                one payroll row of that chamber that year does
--   by name      payroll "LAST, FIRST" against the official's name variants within the same group of
--                offices, first names sharing their first three letters (Doug/Douglas): statewide officials,
--                judges, and legislator rows the seat match leaves open (shared surnames, members without
--                an Open States seat)
-- match_confidence is 'high' when the first name also matches exactly, else 'medium'. Ambiguous rows are
-- dropped.
-- Federal officials (Congress, federal judges) are paid by the U.S., whose pay isn't published per person;
-- their rows are the statutory salary of the office (seed federal_salaries) for each year they held it:
-- Congress from every congress-legislators term, judges from their commission (current court only).
-- pay_basis tells the two apart.
with pay as (
    select
        p.*,
        t.office_group,
        case
            when p.position_title like 'STATE REPRESENTATIVE%' then 'lower'
            when t.office_group = 'legislature' then 'upper'
        end as seat_chamber,
        {{ mogov.name_key('p.last_name') }} as last_key,
        {{ mogov.name_key(dbt.split_part('p.first_names', "' '", 1)) }} as first_key
    from {{ ref('stg_mo_employee_pay__pay') }} as p
    inner join {{ ref('mo_payroll_office_titles') }} as t
        on p.agency_name = t.agency_name and p.position_title = t.position_title
),

-- legislature: by seat ----------------------------------------------------------------------------------
seat_years as (
    select distinct
        s.person_id,
        s.chamber,
        s.surname_key,
        {{ mogov.name_key(dbt.split_part('s.full_name', "' '", 1)) }} as given_key,
        y.calendar_year
    from {{ ref('int_mo_legislators__seats') }} as s
    inner join (select distinct calendar_year from pay) as y
        on
            y.calendar_year between extract(year from s.start_date) and extract(year from s.end_date)
),

seat_candidates as (
    select
        p.*,
        s.person_id,
        s.given_key,
        count(distinct s.person_id) over (
            partition by p.calendar_year, p.seat_chamber, p.last_key, p.employee_name
        ) as n_members,
        count(distinct p.employee_name) over (
            partition by p.calendar_year, p.seat_chamber, p.last_key, s.person_id
        ) as n_payees
    from pay as p
    inner join seat_years as s
        on
            p.calendar_year = s.calendar_year
            and p.seat_chamber = s.chamber
            and p.last_key = s.surname_key
    where p.office_group = 'legislature'
),

by_seat as (
    select
        o.official_id,
        c.calendar_year,
        c.agency_name,
        c.position_title,
        c.employee_name,
        c.gross_pay,
        case when c.first_key = c.given_key then 'high' else 'medium' end as match_confidence
    from seat_candidates as c
    inner join {{ ref('dim_official') }} as o on c.person_id = o.official_id
    where c.n_members = 1 and c.n_payees = 1
),

-- by name -----------------------------------------------------------------------------------------------
officials as (
    select distinct
        official_id,
        family_key,
        given_key,
        case
            when office in ('state_house', 'state_senate') then 'legislature'
            when office like 'mo_%' then 'judiciary'
            else 'statewide'
        end as office_group
    from {{ ref('int_officials__name_keys') }}
    where level = 'state'
),

open_pay as (
    select p.*
    from pay as p
    left join by_seat as b
        on
            p.calendar_year = b.calendar_year
            and p.agency_name = b.agency_name
            and p.position_title = b.position_title
            and p.employee_name = b.employee_name
    where b.official_id is null
),

name_candidates as (
    select
        o.official_id,
        p.calendar_year,
        p.agency_name,
        p.position_title,
        p.employee_name,
        p.gross_pay,
        max(case when p.first_key = o.given_key then 1 else 0 end) as exact_first
    from open_pay as p
    inner join officials as o
        on
            (
                p.office_group = o.office_group
                or (p.office_group in ('legislature', 'statewide') and o.office_group in ('legislature', 'statewide'))
            )
            and p.last_key = o.family_key
            and left(p.first_key, 3) = left(o.given_key, 3)
    group by o.official_id, p.calendar_year, p.agency_name, p.position_title, p.employee_name, p.gross_pay
),

by_name as (
    select
        official_id,
        calendar_year,
        agency_name,
        position_title,
        employee_name,
        gross_pay,
        case when exact_first = 1 then 'high' else 'medium' end as match_confidence,
        count(distinct official_id) over (
            partition by calendar_year, agency_name, position_title, employee_name, gross_pay
        ) as n_officials,
        count(*) over (partition by official_id, calendar_year, agency_name, position_title) as n_rows
    from name_candidates
),

by_name_kept as (
    select
        official_id,
        calendar_year,
        agency_name,
        position_title,
        employee_name,
        gross_pay,
        match_confidence
    from by_name
    where n_officials = 1 and n_rows = 1
),

matched as (
    select * from by_seat
    union all
    select b.*
    from by_name_kept as b
    -- an official the seat match already paid for this position and year keeps that row
    left join by_seat as s
        on
            b.official_id = s.official_id
            and b.calendar_year = s.calendar_year
            and b.agency_name = s.agency_name
            and b.position_title = s.position_title
    where s.official_id is null
),

-- federal: statutory salary per year in office ----------------------------------------------------------
federal_years as (
    -- a Congress ends at noon on January 3, so its last calendar year is the one before end_date
    select distinct
        o.official_id,
        o.full_name,
        case t.term_type when 'sen' then 'us_senate' else 'us_house' end as office,
        extract(year from t.start_date) as first_year,
        extract(year from {{ dbt.dateadd('day', -4, 't.end_date') }}) as last_year
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('stg_congress__terms') }} as t on o.bioguide_id = t.bioguide_id
    where t.state = 'MO'
    union all
    select
        official_id,
        full_name,
        office,
        extract(year from current_term_start) as first_year,
        coalesce(extract(year from current_term_end), extract(year from current_date)) as last_year
    from {{ ref('dim_official') }}
    where office in ('us_district_court', 'us_court_of_appeals')
),

federal as (
    select distinct
        y.official_id,
        s.calendar_year,
        case when y.office in ('us_house', 'us_senate') then 'U.S. CONGRESS' else 'U.S. COURTS' end as agency_name,
        s.position_title,
        y.full_name as employee_name,
        {{ dbt.safe_cast('s.annual_salary', 'decimal(12, 2)') }} as pay,
        s.source_url
    from federal_years as y
    inner join {{ ref('federal_salaries') }} as s
        on
            y.office = s.office
            and s.calendar_year between y.first_year and y.last_year
            and s.calendar_year <= extract(year from current_date)
)

select
    official_id,
    calendar_year,
    agency_name,
    position_title,
    employee_name,
    gross_pay as pay,
    'gross pay' as pay_basis,
    match_confidence,
    'https://mapyourtaxes.mo.gov/MAP/Employees/' as source_url
from matched

union all

select
    official_id,
    calendar_year,
    agency_name,
    position_title,
    employee_name,
    pay,
    'statutory salary' as pay_basis,
    'high' as match_confidence,
    source_url
from federal
