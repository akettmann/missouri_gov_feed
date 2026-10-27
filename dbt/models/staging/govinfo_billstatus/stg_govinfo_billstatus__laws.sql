-- Law numbers of federal bills from the GovInfo BILLSTATUS bulk XML, one row per (bill, law). Only bills that were
-- enacted have one. law_type is "Public Law" or "Private Law"; law_number is "<congress>-<n>" (118-1) and is numbered
-- separately per type, so 118-5 can exist as both. A bill can carry two (a measure folded into another).
-- law_congress and law_sequence are the two parts as integers, because the text sorts wrongly ("118-100" < "118-21").
with laws as (
    select
        {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
        {{ mogov.json_str('payload', '$.law_type') }} as law_type,
        {{ mogov.json_str('payload', '$.law_number') }} as law_number,
        source_url
    from {{ source('govinfo_billstatus', 'laws') }}
)

select
    bill_id,
    law_type,
    law_number,
    {{ dbt.safe_cast(dbt.split_part('law_number', "'-'", 1), dbt.type_int()) }} as law_congress,
    {{ dbt.safe_cast(dbt.split_part('law_number', "'-'", 2), dbt.type_int()) }} as law_sequence,
    source_url
from laws
