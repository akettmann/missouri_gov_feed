{{ config(enabled=var('mec_direct', false)) }}
-- MEC lobbyist expenditures on officials, 2019+ (direct export). recipient is "Last,  First  - Role".
select
    mecid_l as lobbyist_id,
    trim(coalesce(lobbyist_first_name, '') || ' ' || coalesce(lobbyist_last_name, '')) as lobbyist_name,
    principal as principal_name,
    recipient as recipient_raw,
    trim({{ dbt.split_part('recipient', "' - '", 2) }}) as recipient_title,
    trim({{ dbt.split_part(dbt.split_part('recipient', "' - '", 1), "','", 1) }}) as recipient_last,
    trim({{ dbt.split_part(dbt.split_part('recipient', "' - '", 1), "','", 2) }}) as recipient_first,
    expenditure_category,
    expenditure_type,
    trim(description) as description,
    {{ dbt.safe_cast("replace(expenditure_amount, ',', '')", dbt.type_numeric()) }} as amount,
    {{ mogov.parse_date('expenditure_date', '%m/%d/%Y') }} as expenditure_date,
    amended
from {{ source('mec', 'lobbyist_expenditures') }}
