-- Missouri state expenditures: one payee's total for a fiscal year (July to June) per agency and detail line, not one
-- payment. Payees are people (legislators: "LAST, FIRST MIDDLE") and vendors alike. Negative totals are refunds
-- and corrections and are kept. The portal serves an occasional sparse row with only a few of the columns filled
-- (FY2025: fiscal_year "KEVIN KRAUS"); a row without a numeric fiscal year, payee or total is left out here.
with payments as (
    select
        record_key,
        source_url,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.fiscal_year'), dbt.type_int()) }} as fiscal_year,
        trim({{ mogov.json_str('payload', '$.agency_name') }}) as agency_name,
        trim({{ mogov.json_str('payload', '$.category_description') }}) as category_description,
        trim({{ mogov.json_str('payload', '$.detail_description') }}) as detail_description,
        trim({{ mogov.json_str('payload', '$.vendor_name') }}) as vendor_name,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.payments_total'), 'decimal(16, 2)') }} as payments_total
    from {{ source('mo_state_expenditures', 'payments') }}
)

select *
from payments
where fiscal_year is not null and vendor_name is not null and payments_total is not null
