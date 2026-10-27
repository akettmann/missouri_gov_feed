-- Committees (and subcommittees) federal bills were referred to, from the GovInfo BILLSTATUS bulk XML: one row per
-- (bill, committee) and one per (bill, subcommittee). A subcommittee row has subposition set and parent_system_code
-- naming its committee; the file gives it no chamber, so it takes its parent's. system_code is Congress.gov's
-- committee code (hsba00 House Financial Services; a subcommittee code ends in a non-zero number, hsif03).
-- The dated steps (referred, markup, reported) are in stg_govinfo_billstatus__committee_activities.
with src as (
    select
        {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.subposition'), dbt.type_int()) }} as subposition,
        {{ mogov.json_str('payload', '$.system_code') }} as system_code,
        {{ mogov.json_str('payload', '$.parent_system_code') }} as parent_system_code,
        {{ mogov.json_str('payload', '$.name') }} as name,
        {{ mogov.json_str('payload', '$.chamber') }} as chamber,
        {{ mogov.json_str('payload', '$.committee_type') }} as committee_type,
        source_url
    from {{ source('govinfo_billstatus', 'committees') }}
)

select
    src.bill_id,
    src.position,
    src.subposition,
    src.system_code,
    src.parent_system_code,
    src.name,
    coalesce(src.chamber, parent.chamber) as chamber,
    coalesce(src.committee_type, parent.committee_type) as committee_type,
    src.subposition is not null as is_subcommittee,
    src.source_url
from src
left join src as parent
    on
        src.subposition is not null
        and parent.subposition is null
        and src.bill_id = parent.bill_id
        and src.position = parent.position
