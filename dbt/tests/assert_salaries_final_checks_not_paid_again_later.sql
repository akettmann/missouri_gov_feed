-- A final check is a small payroll payment to a legislator whose seat ended the December before (or that January);
-- fct_salaries sets it aside and, for a departed member, matches it by name (#250, #269, #471). The edge case:
-- a successor who joins mid-year by special election with the same surname and a fitting first name, and only a
-- partial year's pay, would look like the departed member's final check. A real final check is the payee's last
-- pay, so a final-check payee who is paid in the same chamber in a later year is a suspect and is listed here.
-- The final checks are int_mo_legislators__final_checks. The check joins payroll on the exact employee_name.
select
    f.calendar_year as final_check_year,
    f.seat_chamber,
    f.employee_name,
    f.person_id,
    l.calendar_year as later_pay_year
from {{ ref('int_mo_legislators__final_checks') }} as f
inner join {{ ref('stg_mo_employee_pay__pay') }} as l
    on
        f.employee_name = l.employee_name
        and f.calendar_year < l.calendar_year
inner join {{ ref('mo_payroll_office_titles') }} as t
    on l.agency_name = t.agency_name and l.position_title = t.position_title
where
    t.office_group = 'legislature'
    and f.seat_chamber = case when l.position_title like 'STATE REPRESENTATIVE%' then 'lower' else 'upper' end
