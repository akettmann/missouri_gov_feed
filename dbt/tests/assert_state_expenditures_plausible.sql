-- Sanity bounds on the state expenditures (the largest total seen is $11.24B, Medicaid recipients in fiscal 2026):
-- a fiscal year outside 2000 to next year, a total beyond $20B in either direction, or a legislator's per diem
-- or mileage line beyond $30,000 for the year (per diem tops out near $11,500). Each is a row.
select
    fiscal_year,
    agency_name,
    detail_description,
    vendor_name,
    payments_total
from {{ ref('stg_mo_state_expenditures__payments') }}
where
    fiscal_year not between 2000 and extract(year from current_date) + 1
    or abs(payments_total) > 20000000000
    or (
        agency_name = 'LEGISLATURE'
        and detail_description in ('LEGISLATIVE DAILY EXPENSE ALLOWANCE', 'IN-STATE MILEAGE')
        and payments_total not between -30000 and 30000
    )
