-- Legislator payroll rows that are a departed member's final check: a small payment to a payee whose surname and
-- first name fit a member of the same chamber whose seat ended the December before the pay year, or that January
-- (Open States ends the 2022 and 2024 departures on 2023-01-03 and 2025-01-07), and who was paid well under a
-- full year's salary (under half of the year's highest pay for the position). It is that departed member's last
-- pay, unless the member later held a seat in the chamber again, so neither it nor the member competes for the
-- seats held now ("BLACK, LINDA R." 2017 is Linda Black's, not a second claimant to Rusty Black's seat, whose
-- middle initial it shares, #250). fct_salaries sets these rows aside and, for a departed member, matches them by
-- name only (#269, #471). The payee is identified by the payroll's employee_name, exactly as printed.
with pay as (
    select
        p.calendar_year,
        p.employee_name,
        p.gross_pay,
        p.first_names,
        {{ dbt.replace(mogov.surname_key('p.last_name'), "' '", "''") }} as last_flat,
        {{ mogov.name_key(dbt.split_part('p.first_names', "' '", 1)) }} as first_key,
        {{ mogov.name_key('p.first_names') }} as first_all_key,
        case when p.position_title like 'STATE REPRESENTATIVE%' then 'lower' else 'upper' end as seat_chamber,
        max(p.gross_pay) over (partition by p.calendar_year, p.position_title) as top_pay
    from {{ ref('stg_mo_employee_pay__pay') }} as p
    inner join {{ ref('mo_payroll_office_titles') }} as t
        on p.agency_name = t.agency_name and p.position_title = t.position_title
    where t.office_group = 'legislature'
)

select distinct
    p.calendar_year,
    p.seat_chamber,
    p.employee_name,
    d.person_id
from pay as p
inner join {{ ref('int_mo_legislators__seats') }} as d
    on
        p.seat_chamber = d.chamber
        -- the seat ended in December of the year before, or in January of this year
        and (
            (extract(year from d.end_date) = p.calendar_year - 1 and extract(month from d.end_date) = 12)
            or (extract(year from d.end_date) = p.calendar_year and extract(month from d.end_date) = 1)
        )
        and {{ dbt.replace('d.surname_key', "' '", "''") }} = p.last_flat
        and {{
            mogov.first_name_fit(
                'p.first_key',
                'p.first_all_key',
                mogov.name_key(dbt.split_part('d.full_name', "' '", 1))
            )
        }} >= 1
where
    p.gross_pay * 2 < p.top_pay
    and not exists (
        select 1
        from {{ ref('int_mo_legislators__seats') }} as later
        where
            later.person_id = d.person_id
            and later.chamber = d.chamber
            and later.end_date > d.end_date
    )
