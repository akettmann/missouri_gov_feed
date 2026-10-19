-- MEC lobbyist expenditures on public officials (meals, gifts, travel...), TAP mirror 2004-2022.
-- recipient_name is "LAST, FIRST"; group expenditures (e.g. "ENTIRE SENATE") have no individual name.
select
    lob_id as lobbyist_id,
    trim(coalesce(lob_first_name, '') || ' ' || coalesce(lob_last_name, '')) as lobbyist_name,
    principal_name,
    coalesce(recipient_name, public_official_name) as recipient_name,
    coalesce(recipient_title, public_official_title) as recipient_title,
    recipient as recipient_raw,
    expenditure_category,
    expenditure_type,
    description,
    {{ dbt.safe_cast("replace(prin_amount, ',', '')", dbt.type_numeric()) }} as amount,
    {{ dbt.safe_cast('expenditure_date', 'date') }} as expenditure_date,
    {{ dbt.safe_cast('year', dbt.type_int()) }} as expenditure_year,
    trim({{ dbt.split_part('coalesce(recipient_name, public_official_name)', "','", 1) }}) as recipient_last,
    trim({{ dbt.split_part('coalesce(recipient_name, public_official_name)', "','", 2) }}) as recipient_first
from {{ source('tap_mec', 'lobbyist_expenditures') }}
where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
