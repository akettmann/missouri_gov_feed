-- MEC itemized expenditures by Missouri committees (TAP mirror, 2011-2022): includes contributions the
-- committee made to other candidates and committees.
select
    mecid as mec_committee_id,
    committee_name,
    coalesce(payee_name, company, trim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))) as payee_name,
    purpose,
    expenditure_type,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ dbt.safe_cast('date_clean', 'date') }} as expenditure_date,
    {{ dbt.safe_cast('year_clean', dbt.type_int()) }} as expenditure_year,
    city_final as payee_city,
    state_norm as payee_state,
    report
from {{ source('tap_mec', 'expenditures') }}
where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
