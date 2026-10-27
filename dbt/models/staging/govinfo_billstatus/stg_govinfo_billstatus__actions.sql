-- Actions on federal bills from the GovInfo BILLSTATUS bulk XML, one row per (bill, action) in the file's order. A file
-- lists a House or Senate action and often the Library of Congress's coded copy of it (source_system), so counts of
-- rows overcount actions; action_type is as published (President, Veto, BecameLaw, Floor, ...).
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.action_date'), 'date') }} as action_date,
    {{ mogov.json_str('payload', '$.action_time') }} as action_time,
    {{ mogov.json_str('payload', '$.text') }} as action_text,
    {{ mogov.json_str('payload', '$.action_type') }} as action_type,
    {{ mogov.json_str('payload', '$.action_code') }} as action_code,
    {{ mogov.json_str('payload', '$.source_system') }} as source_system,
    source_url
from {{ source('govinfo_billstatus', 'actions') }}
