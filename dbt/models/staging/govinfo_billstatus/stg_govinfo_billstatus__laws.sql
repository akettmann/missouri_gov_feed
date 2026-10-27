-- Public Law numbers of federal bills from the GovInfo BILLSTATUS bulk XML, one row per (bill, law). Only bills that
-- were enacted have one; law_number is "<congress>-<n>" (118-1). A bill can carry two (a measure folded into another).
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ mogov.json_str('payload', '$.law_type') }} as law_type,
    {{ mogov.json_str('payload', '$.law_number') }} as law_number,
    source_url
from {{ source('govinfo_billstatus', 'laws') }}
