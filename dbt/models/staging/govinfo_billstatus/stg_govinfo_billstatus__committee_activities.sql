-- Dated steps of a federal bill in a committee or subcommittee, from the GovInfo BILLSTATUS bulk XML: one row per
-- (bill, committee or subcommittee, activity). activity is the label as published ("Referred to", "Markup by",
-- "Reported by", "Hearings by", "Discharged from"); the wording differs between the House and Senate and over time
-- ("Referred To" vs "Referred to", "Markup by" vs "Markup By"), so filter on activity_normalized (lower case, hyphens
-- as spaces, trimmed). activity_date is null only for "Bills of Interest - Exchange of Letters", which the file
-- publishes without a date. position / subposition point at the row in
-- stg_govinfo_billstatus__committees (subposition is null for a full committee).
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.subposition'), dbt.type_int()) }} as subposition,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.activity_position'), dbt.type_int()) }} as activity_position,
    {{ mogov.json_str('payload', '$.system_code') }} as system_code,
    {{ mogov.json_str('payload', '$.activity') }} as activity,
    lower(trim(replace({{ mogov.json_str('payload', '$.activity') }}, '-', ' '))) as activity_normalized,
    {{ dbt.safe_cast("substring(" ~ mogov.json_str('payload', '$.activity_date') ~ ", 1, 10)", 'date') }}
        as activity_date,
    source_url
from {{ source('govinfo_billstatus', 'committee_activities') }}
