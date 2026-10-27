-- Federal bill cosponsors from the GovInfo BILLSTATUS bulk XML, one row per (bill, cosponsor). A cosponsor who later
-- withdrew keeps the row with sponsorship_withdrawn_date set. is_original_cosponsor is true when the member signed on
-- when the bill was introduced; state and district are the member's at the time of the bill.
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ mogov.json_str('payload', '$.bioguide_id') }} as bioguide_id,
    {{ mogov.json_str('payload', '$.full_name') }} as full_name,
    {{ mogov.json_str('payload', '$.party') }} as party,
    {{ mogov.json_str('payload', '$.state') }} as state,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.district'), dbt.type_int()) }} as district,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.sponsorship_date'), 'date') }} as sponsorship_date,
    {{ mogov.json_str('payload', '$.is_original_cosponsor') }} = 'True' as is_original_cosponsor,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.sponsorship_withdrawn_date'), 'date') }}
        as sponsorship_withdrawn_date,
    source_url
from {{ source('govinfo_billstatus', 'cosponsors') }}
