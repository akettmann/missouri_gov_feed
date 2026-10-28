-- Actions on federal bill amendments from the GovInfo BILLSTATUS bulk XML, one row per (amendment, action) in the
-- file's order. As for bills, a chamber action is often followed by the Library of Congress's coded copy of it
-- (source_system), so counts of rows overcount actions.
select
    {{ mogov.json_str('payload', '$.amendment_id') }} as amendment_id,
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.action_date'), 'date') }} as action_date,
    {{ mogov.json_str('payload', '$.action_time') }} as action_time,
    {{ mogov.json_str('payload', '$.text') }} as action_text,
    {{ mogov.json_str('payload', '$.action_type') }} as action_type,
    {{ mogov.json_str('payload', '$.action_code') }} as action_code,
    {{ mogov.json_str('payload', '$.source_system') }} as source_system,
    source_url
from {{ source('govinfo_billstatus', 'amendment_actions') }}
