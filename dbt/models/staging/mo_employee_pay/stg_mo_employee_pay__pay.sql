-- Missouri state payroll rows: calendar-year gross pay (all pay received, not base salary) per employee,
-- agency and position. Names are printed "LAST, FIRST M"; split here for matching.
select
    {{ dbt.safe_cast('calendar_year', dbt.type_int()) }} as calendar_year,
    trim(agency_name) as agency_name,
    trim(position_title) as position_title,
    trim(employee_name) as employee_name,
    trim({{ dbt.split_part('employee_name', "','", 1) }}) as last_name,
    trim({{ dbt.split_part('employee_name', "','", 2) }}) as first_names,
    {{ dbt.safe_cast('ytd_gross_pay', 'decimal(12, 2)') }} as gross_pay
from {{ source('mo_employee_pay', 'pay') }}
