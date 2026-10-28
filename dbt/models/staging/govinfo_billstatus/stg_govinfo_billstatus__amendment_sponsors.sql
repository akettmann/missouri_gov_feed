-- Sponsors of federal bill amendments from the GovInfo BILLSTATUS bulk XML, one row per (amendment, sponsor).
-- role is "sponsor" or "on_behalf_of" (a senator offering an amendment on another senator's behalf). A House
-- committee can sponsor an amendment ("Rules Committee"): bioguide_id is then null and name carries the committee.
-- bioguide_id joins congress_legislators. The file sometimes lists the same member twice, under two spellings of the
-- name, so a member can appear twice for an amendment; position keeps the file's order.
select
    {{ mogov.json_str('payload', '$.amendment_id') }} as amendment_id,
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ mogov.json_str('payload', '$.role') }} as role,
    {{ mogov.json_str('payload', '$.bioguide_id') }} as bioguide_id,
    coalesce({{ mogov.json_str('payload', '$.full_name') }}, {{ mogov.json_str('payload', '$.name') }}) as name,
    {{ mogov.json_str('payload', '$.party') }} as party,
    {{ mogov.json_str('payload', '$.state') }} as state,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.district'), dbt.type_int()) }} as district,
    {{ mogov.json_str('payload', '$.bioguide_id') }} is null as is_committee,
    source_url
from {{ source('govinfo_billstatus', 'amendment_sponsors') }}
