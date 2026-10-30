-- Federal bill sponsors from the GovInfo BILLSTATUS bulk XML, one row per (bill, sponsor). bioguide_id joins
-- congress_legislators; state and district are the member's at the time of the bill (district is null for senators).
-- is_by_request is Y when the sponsor introduced the bill by request of the executive.
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ mogov.json_str('payload', '$.bioguide_id') }} as bioguide_id,
    {{ mogov.json_str('payload', '$.full_name') }} as full_name,
    {{ mogov.json_str('payload', '$.party') }} as party,
    {{ mogov.json_str('payload', '$.state') }} as state,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.district'), dbt.type_int()) }} as district,
    {{ mogov.json_str('payload', '$.is_by_request') }} as is_by_request,
    source_url
from {{ source('govinfo_billstatus', 'sponsors') }}
