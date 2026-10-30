-- CRS legislative subject terms of federal bills, from the GovInfo BILLSTATUS bulk XML: one row per (bill, subject).
-- The terms are the Congressional Research Service's controlled vocabulary ("Taxation", "Health care coverage and
-- access"); a bill's single broader policy area is policy_area in stg_govinfo_billstatus__bills. The CRS tags a bill
-- only after it is introduced, so a new bill can have none yet.
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ mogov.json_str('payload', '$.name') }} as subject,
    {{ dbt.safe_cast("substring(" ~ mogov.json_str('payload', '$.update_date') ~ ", 1, 10)", 'date') }} as update_date,
    source_url
from {{ source('govinfo_billstatus', 'subjects') }}
