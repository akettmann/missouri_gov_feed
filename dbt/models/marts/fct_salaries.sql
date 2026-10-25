-- Pay received by current state officials as officeholders, per calendar year, from the state payroll
-- (data.mo.gov State Employee Pay, 2017+). Gross pay is all pay received in the year, not the base salary;
-- a year with a change of office has a row per position. Only officeholder titles count
-- (seed mo_payroll_office_titles), never staff positions.
-- The payroll prints legal names ("LUETKEMEYER, ANTON H" for Tony Luetkemeyer, "BLACK, JAMES R" for Rusty
-- Black), so legislators are matched by seat instead of first name:
--   legislature  surname + chamber + year against every legislator's seats (int_mo_legislators__seats). The
--                payroll surname is compared without suffixes the payroll prints inside it ("BRATTIN JR.",
--                "HADEN DVM"), with spaces ignored ("VANSCHOIACK" = Van Schoiack), and, when the first name
--                fits too, by its last words ("WALSH MOORE" for Moore). Kept when
--                  1. exactly one member of that chamber that year has the surname and exactly one payee does, or
--                  2. several share it and a payee and a member are each other's only best first-name fit
--                     (Ed = EDWIN, Patty = PATRICIA), or
--                  3. a payee's middle initial is the initial of the name a member goes by, and no one else fits
--                     that way ("SMITH, DAVID C" is Cody Smith), or
--                  4. once 1 to 3 have paired the rest, one payee and one member remain (Mike Jones =
--                     JONES, MICHAEL J after Holly Jones)
--                A seat counts from the member's first roster year when Open States has no start date (#227).
--   by name      payroll "LAST, FIRST" against the official's name variants within the same group of
--                offices, first names that fit (see mogov.first_name_fit): statewide officials, judges, and
--                legislator rows the seat match leaves open (members without an Open States seat), and only in
--                the years a legislator sat unless nobody else holds the surname that year
-- match_confidence is 'high' when the first name also matches exactly, else 'medium' (a nickname, or the
-- given name found among several payroll first names). Ambiguous rows are dropped.
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
        {{ mogov.surname_key('p.last_name') }} as last_key,
        {{ dbt.replace(mogov.surname_key('p.last_name'), "' '", "''") }} as last_flat,
        {{ mogov.name_key(dbt.split_part('p.first_names', "' '", 1)) }} as first_key,
        {{ mogov.name_key('p.first_names') }} as first_all_key,
        {{ mogov.name_key(dbt.split_part('p.first_names', "' '", 2)) }} as middle_key
    from {{ ref('stg_mo_employee_pay__pay') }} as p
    inner join {{ ref('mo_payroll_office_titles') }} as t
        on p.agency_name = t.agency_name and p.position_title = t.position_title
),

-- legislature: by seat ----------------------------------------------------------------------------------
-- The first year each member really sat in a chamber (a roster year). Open States gives some seats no start date,
-- which int_mo_legislators__seats turns into 1900-01-01; such a seat starts here instead, so pay from the years
-- before the member took office never pairs with them (#227). Members with no roster year keep the placeholder.
first_roster_years as (
    select
        official_id as person_id,
        case office when 'state_house' then 'lower' else 'upper' end as chamber,
        min(year) as first_year
    from {{ ref('int_officeholders__years') }}
    where office in ('state_house', 'state_senate')
    group by official_id, case office when 'state_house' then 'lower' else 'upper' end
),

seat_years as (
    select distinct
        s.person_id,
        s.chamber,
        s.surname_key,
        {{ dbt.replace('s.surname_key', "' '", "''") }} as surname_flat,
        {{ mogov.name_key(dbt.split_part('s.full_name', "' '", 1)) }} as given_key,
        y.calendar_year
    from {{ ref('int_mo_legislators__seats') }} as s
    left join first_roster_years as f
        on s.person_id = f.person_id and s.chamber = f.chamber
    inner join (select distinct calendar_year from pay) as y
        on
            y.calendar_year between
            case
                when s.start_date > {{ dbt.safe_cast("'1900-01-01'", 'date') }} then extract(year from s.start_date)
                else coalesce(f.first_year, extract(year from s.start_date))
            end
            and extract(year from s.end_date)
),

-- the years a member sat, to hold a by-name match of legislator pay to them
service_years as (
    select
        person_id,
        min(calendar_year) as first_year,
        max(calendar_year) as last_year
    from seat_years
    group by person_id
),

-- every (payroll row, member of the same chamber and year) pair whose surnames agree: the whole surname
-- (spaces ignored, so VANSCHOIACK = Van Schoiack), or its last words ("WALSH MOORE" for Moore), which also
-- needs the first name to fit
seat_pairs_raw as (
    select
        p.calendar_year,
        p.agency_name,
        p.position_title,
        p.employee_name,
        p.gross_pay,
        p.seat_chamber,
        s.person_id,
        p.last_flat = s.surname_flat as same_surname,
        {{ mogov.first_name_fit('p.first_key', 'p.first_all_key', 's.given_key') }} as name_fit,
        -- the payee's middle initial is the initial of the name the member goes by ("SMITH, DAVID C" is
        -- Cody Smith)
        length(p.middle_key) = 1 and length(s.given_key) >= 2 and left(s.given_key, 1) = p.middle_key as initial_fit
    from pay as p
    inner join seat_years as s
        on
            p.calendar_year = s.calendar_year
            and p.seat_chamber = s.chamber
            and (p.last_flat = s.surname_flat or p.last_key like '% ' || s.surname_key)
    where p.office_group = 'legislature'
),

seat_pairs as (
    select
        *,
        count(distinct person_id) over (partition by calendar_year, seat_chamber, employee_name) as n_members,
        count(distinct employee_name) over (partition by calendar_year, seat_chamber, person_id) as n_payees,
        max(name_fit) over (partition by calendar_year, seat_chamber, employee_name) as payee_best,
        max(name_fit) over (partition by calendar_year, seat_chamber, person_id) as member_best
    from seat_pairs_raw
    where same_surname or name_fit >= 1
),

-- 1. the only member of the chamber with the surname that year, and the only payee
seat_unique as (
    select
        person_id,
        calendar_year,
        seat_chamber,
        employee_name,
        agency_name,
        position_title,
        gross_pay,
        name_fit
    from seat_pairs
    where n_members = 1 and n_payees = 1
),

-- 2. several share the surname: pair those whose first names fit, when each is the other's only best fit
-- (Ed Lewis = LEWIS, EDWIN G; Patty Lewis = LEWIS, PATRICIA)
seat_fitted as (
    select
        *,
        count(distinct person_id) over (partition by calendar_year, seat_chamber, employee_name) as n_best_members,
        count(distinct employee_name) over (partition by calendar_year, seat_chamber, person_id) as n_best_payees
    from seat_pairs
    where name_fit >= 1 and name_fit = payee_best and name_fit = member_best
),

seat_matched as (
    select * from seat_unique
    union
    select
        person_id,
        calendar_year,
        seat_chamber,
        employee_name,
        agency_name,
        position_title,
        gross_pay,
        name_fit
    from seat_fitted
    where n_best_members = 1 and n_best_payees = 1
),

-- what is left of a shared surname after steps 1 and 2
seat_open as (
    select p.*
    from seat_pairs as p
    left join seat_matched as m_payee
        on
            p.calendar_year = m_payee.calendar_year
            and p.seat_chamber = m_payee.seat_chamber
            and p.employee_name = m_payee.employee_name
    left join seat_matched as m_member
        on
            p.calendar_year = m_member.calendar_year
            and p.seat_chamber = m_member.seat_chamber
            and p.person_id = m_member.person_id
    where m_payee.person_id is null and m_member.person_id is null
),

-- 3. a payee and a member that fit by the payee's middle initial and no one else does: "SMITH, DAVID C" is
-- Cody Smith, though David Smith fits the first name just as well
seat_initial as (
    select
        *,
        count(distinct person_id) over (partition by calendar_year, seat_chamber, employee_name) as n_init_members,
        count(distinct employee_name) over (partition by calendar_year, seat_chamber, person_id) as n_init_payees
    from seat_open
    where initial_fit and same_surname
),

seat_initial_matched as (
    select
        person_id,
        calendar_year,
        agency_name,
        position_title,
        employee_name,
        gross_pay,
        seat_chamber
    from seat_initial
    where n_init_members = 1 and n_init_payees = 1
),

-- 4. what is left once 1 to 3 have paired the rest: one payee and one member with nobody else to pair with,
-- though their first names don't fit (Mike Jones = JONES, MICHAEL J after Holly Jones; David Smith =
-- SMITH, DAVID T after Cody Smith)
seat_left as (
    select
        p.person_id,
        p.calendar_year,
        p.agency_name,
        p.position_title,
        p.employee_name,
        p.gross_pay,
        count(distinct p.person_id)
            over (partition by p.calendar_year, p.seat_chamber, p.employee_name)
            as n_left_members,
        count(distinct p.employee_name)
            over (partition by p.calendar_year, p.seat_chamber, p.person_id)
            as n_left_payees
    from seat_open as p
    left join seat_initial_matched as i_payee
        on
            p.calendar_year = i_payee.calendar_year
            and p.seat_chamber = i_payee.seat_chamber
            and p.employee_name = i_payee.employee_name
    left join seat_initial_matched as i_member
        on
            p.calendar_year = i_member.calendar_year
            and p.seat_chamber = i_member.seat_chamber
            and p.person_id = i_member.person_id
    where i_payee.person_id is null and i_member.person_id is null
),

seat_resolved as (
    select
        person_id,
        calendar_year,
        agency_name,
        position_title,
        employee_name,
        gross_pay,
        case when name_fit = 3 then 'high' else 'medium' end as match_confidence
    from seat_matched
    union all
    select
        person_id,
        calendar_year,
        agency_name,
        position_title,
        employee_name,
        gross_pay,
        'medium' as match_confidence
    from seat_left
    where n_left_members = 1 and n_left_payees = 1
    union all
    select
        person_id,
        calendar_year,
        agency_name,
        position_title,
        employee_name,
        gross_pay,
        'medium' as match_confidence
    from seat_initial_matched
),

by_seat as (
    select
        o.official_id,
        r.calendar_year,
        r.agency_name,
        r.position_title,
        r.employee_name,
        r.gross_pay,
        r.match_confidence
    from seat_resolved as r
    inner join {{ ref('dim_official') }} as o on r.person_id = o.official_id
),

-- by name -----------------------------------------------------------------------------------------------
officials as (
    select distinct
        official_id,
        family_key,
        {{ dbt.replace('family_key', "' '", "''") }} as family_flat,
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
            and p.last_flat = o.family_flat
            and {{ mogov.first_name_fit('p.first_key', 'p.first_all_key', 'o.given_key') }} >= 1
    left join service_years as w on o.official_id = w.person_id
    -- legislator pay outside the years the member sat is another member's, when a member of that chamber that
    -- year shares the surname and none has the member's first name ("SMITH, DAVID C" in 2017-20 is Cody
    -- Smith's, not David Smith's, #227). With nobody else to claim it, it stays: a final check after a term
    -- ended (Hough, 2017), or earlier service Open States records as another person (Steve Roberts' House years
    -- as "Steven Roberts").
    where
        p.office_group <> 'legislature'
        or w.person_id is null
        or p.calendar_year between w.first_year and w.last_year
        or not exists (
            select 1
            from seat_years as h
            where
                h.calendar_year = p.calendar_year
                and h.chamber = p.seat_chamber
                and h.surname_flat = o.family_flat
                and h.person_id <> o.official_id
        )
        or exists (
            select 1
            from seat_years as h
            where
                h.calendar_year = p.calendar_year
                and h.chamber = p.seat_chamber
                and h.surname_flat = o.family_flat
                and h.person_id <> o.official_id
                and {{ mogov.first_name_fit('h.given_key', 'h.given_key', 'o.given_key') }} >= 1
        )
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
