{{ config(enabled=var('mec_direct', false)) }}
-- MEC itemized expenditures over $100 (CD3 Part B, direct export, recent report years): what each committee
-- paid, to whom, for what. Contributions to other committees are reported separately (CD3 Part C).
select
    cd3_b_id as record_id,
    mecid as mec_committee_id,
    committee_name,
    coalesce(nullif(trim(company), ''), trim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))) as payee_name,
    trim(city) as payee_city,
    state as payee_state,
    purpose,
    expenditure_type,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ mogov.parse_date(dbt.split_part('date', "' '", 1), '%m/%d/%Y') }} as expenditure_date,
    report
from {{ source('mec', 'cd3_b') }}
