-- A final check is a small payroll payment to a legislator whose seat ended the December before (or that January);
-- fct_salaries sets it aside and, for a January departure, matches it by name (#250, #269, #471). The edge case:
-- a successor who joins mid-year by special election with the same surname and a fitting first name, and only a
-- partial year's pay, would look like the departed member's final check. A real final check is the payee's last
-- pay, so a final-check payee who is paid in the same chamber in a later year is a suspect and is listed here.
-- Mirrors the final_checks CTE of fct_salaries (same window, same "under half the top pay" rule, same exclusion of
-- members who held the chamber's seat again).
with pay as (
    select
        p.calendar_year,
        p.employee_name,
        p.gross_pay,
        {{ dbt.replace(mogov.surname_key('p.last_name'), "' '", "''") }} as last_flat,
        p.last_name,
        p.first_names,
        case when p.position_title like 'STATE REPRESENTATIVE%' then 'lower' else 'upper' end as seat_chamber,
        max(p.gross_pay) over (partition by p.calendar_year, p.position_title) as top_pay
    from {{ ref('stg_mo_employee_pay__pay') }} as p
    inner join {{ ref('mo_payroll_office_titles') }} as t
        on p.agency_name = t.agency_name and p.position_title = t.position_title
    where t.office_group = 'legislature'
),

final_checks as (
    select distinct
        p.calendar_year,
        p.seat_chamber,
        p.employee_name,
        d.person_id
    from pay as p
    inner join {{ ref('int_mo_legislators__seats') }} as d
        on
            p.seat_chamber = d.chamber
            and (
                (extract(year from d.end_date) = p.calendar_year - 1 and extract(month from d.end_date) = 12)
                or (extract(year from d.end_date) = p.calendar_year and extract(month from d.end_date) = 1)
            )
            and p.last_flat = {{ dbt.replace('d.surname_key', "' '", "''") }}
            and {{
                mogov.first_name_fit(
                    mogov.name_key(dbt.split_part('p.first_names', "' '", 1)),
                    mogov.name_key('p.first_names'),
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
)

select
    f.calendar_year as final_check_year,
    f.seat_chamber,
    f.employee_name,
    f.person_id,
    l.calendar_year as later_pay_year
from final_checks as f
inner join pay as l
    on
        f.employee_name = l.employee_name
        and f.seat_chamber = l.seat_chamber
        and f.calendar_year < l.calendar_year
