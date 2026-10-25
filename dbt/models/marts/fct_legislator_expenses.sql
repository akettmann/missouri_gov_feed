-- Per diem and in-state mileage the state paid each legislator, per fiscal year (July to June), from the state
-- expenditures (data.mo.gov State Expenditures, agency LEGISLATURE: LEGISLATIVE DAILY EXPENSE ALLOWANCE and
-- IN-STATE MILEAGE). A payee is one payee's annual total for a detail line, not one payment. Negative totals are
-- refunds and stay.
-- The expenditures print the payee's full legal name ("ATCHISON, FRANKLIN DARRELL"), which no official's name
-- matches, so payees are paired through the state payroll (fct_salaries), which prints the same legal names
-- ("ATCHISON, FRANKLIN D", already matched to the official): a payee pairs with a legislature payroll name when
--   1. the surnames agree (spaces and suffixes ignored) and the payroll paid that name in the fiscal year's
--      calendar years (July to December of the year before, and January to June of the fiscal year), and
--   2. the first names fit (see mogov.first_name_fit) and the middle initials, when both have one, agree
--      ("SMITH, DAVID C" is not "SMITH, DAVID T"), and
--   3. exactly one official fits best, and no other payee of that year and line claims the same official.
-- match_confidence is 'high' when the first names are equal and either both names carry the same middle initial or
-- no other legislator on the payroll in those years has the surname; otherwise 'medium'. A surname shared with
-- another legislator is never matched on the surname alone: a payee without a fitting payroll name, or whose
-- fit is shared, is left out.
with expenses as (
    select
        fiscal_year,
        vendor_name,
        case detail_description
            when 'LEGISLATIVE DAILY EXPENSE ALLOWANCE' then 'per diem'
            else 'mileage'
        end as expense_type,
        sum(payments_total) as amount,
        max(source_url) as source_url
    from {{ ref('stg_mo_state_expenditures__payments') }}
    where
        agency_name = 'LEGISLATURE'
        and detail_description in ('LEGISLATIVE DAILY EXPENSE ALLOWANCE', 'IN-STATE MILEAGE')
    group by fiscal_year, vendor_name, detail_description
),

payee_parts as (
    select
        *,
        trim({{ dbt.split_part('vendor_name', "','", 1) }}) as last_name,
        trim({{ dbt.split_part('vendor_name', "','", 2) }}) as first_names
    from expenses
),

payees as (
    select
        *,
        {{ dbt.replace(mogov.surname_key('last_name'), "' '", "''") }} as last_flat,
        {{ mogov.name_key('first_names') }} as first_all_key,
        {{ mogov.name_key(dbt.split_part('first_names', "' '", 1)) }} as first_key,
        coalesce({{ mogov.name_key(dbt.split_part('first_names', "' '", 2)) }}, '') as middle_key
    from payee_parts
),

payroll_parts as (
    select distinct
        official_id,
        calendar_year,
        employee_name,
        trim({{ dbt.split_part('employee_name', "','", 1) }}) as last_name,
        trim({{ dbt.split_part('employee_name', "','", 2) }}) as first_names
    from {{ ref('fct_salaries') }}
    where agency_name = 'LEGISLATURE' and pay_basis = 'gross pay'
),

payroll as (
    select
        official_id,
        calendar_year,
        employee_name,
        {{ dbt.replace(mogov.surname_key('last_name'), "' '", "''") }} as last_flat,
        {{ mogov.name_key(dbt.split_part('first_names', "' '", 1)) }} as first_key,
        coalesce({{ mogov.name_key(dbt.split_part('first_names', "' '", 2)) }}, '') as middle_key
    from payroll_parts
),

pairs as (
    select
        p.fiscal_year,
        p.vendor_name,
        p.expense_type,
        s.official_id,
        {{ mogov.first_name_fit('p.first_key', 'p.first_all_key', 's.first_key') }} as name_fit,
        length(p.middle_key) >= 1 and length(s.middle_key) >= 1 as both_middle
    from payees as p
    inner join payroll as s
        on
            p.last_flat = s.last_flat
            and s.calendar_year in (p.fiscal_year - 1, p.fiscal_year)
    where
        length(p.middle_key) = 0
        or length(s.middle_key) = 0
        or left(p.middle_key, 1) = left(s.middle_key, 1)
),

fitted as (
    select
        fiscal_year,
        vendor_name,
        expense_type,
        official_id,
        max(name_fit) as name_fit,
        max(case when both_middle then 1 else 0 end) as both_middle
    from pairs
    where name_fit >= 1
    group by fiscal_year, vendor_name, expense_type, official_id
),

best as (
    select
        *,
        max(name_fit) over (partition by fiscal_year, vendor_name, expense_type) as payee_best
    from fitted
),

shared_surname as (
    select
        p.fiscal_year,
        p.vendor_name,
        p.expense_type,
        count(distinct s.official_id) as n_officials
    from payees as p
    inner join payroll as s
        on p.last_flat = s.last_flat and s.calendar_year in (p.fiscal_year - 1, p.fiscal_year)
    group by p.fiscal_year, p.vendor_name, p.expense_type
),

matched as (
    select
        b.fiscal_year,
        b.vendor_name,
        b.expense_type,
        b.official_id,
        case
            when b.name_fit = 3 and (b.both_middle = 1 or n.n_officials = 1) then 'high'
            else 'medium'
        end as match_confidence,
        count(*) over (partition by b.fiscal_year, b.vendor_name, b.expense_type) as n_officials,
        count(*) over (partition by b.fiscal_year, b.official_id, b.expense_type) as n_payees
    from best as b
    inner join shared_surname as n
        on b.fiscal_year = n.fiscal_year and b.vendor_name = n.vendor_name and b.expense_type = n.expense_type
    where b.name_fit = b.payee_best
)

select
    m.official_id,
    m.fiscal_year,
    m.expense_type,
    e.vendor_name as payee_name,
    e.amount,
    m.match_confidence,
    e.source_url
from matched as m
inner join expenses as e
    on m.fiscal_year = e.fiscal_year and m.vendor_name = e.vendor_name and m.expense_type = e.expense_type
inner join {{ ref('dim_official') }} as o on m.official_id = o.official_id
where m.n_officials = 1 and m.n_payees = 1
