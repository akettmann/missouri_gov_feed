-- Bills a federal bill is related to, from the GovInfo BILLSTATUS bulk XML: one row per (bill, related bill).
-- related_bill_id has the same form as bill_id ("118-hjres-125"), so it joins stg_govinfo_billstatus__bills when the
-- related bill's Congress is loaded. The kind of relationship (identical, related, procedurally related, a bill folded
-- into another) is in stg_govinfo_billstatus__related_bill_relationships: one related bill can carry several.
-- A relation is usually also listed on the other bill; do not assume it. CRS sometimes lists a bill as related to
-- itself (34 of 12,472 rows in the 118th hr and s); those rows are dropped, so position has gaps.
with src as (
    select
        {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.related_congress'), dbt.type_int()) }} as related_congress,
        lower({{ mogov.json_str('payload', '$.related_bill_type') }}) as related_bill_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.related_number'), dbt.type_int()) }} as related_number,
        {{ mogov.json_str('payload', '$.title') }} as title,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.latest_action_date'), 'date') }} as latest_action_date,
        {{ mogov.json_str('payload', '$.latest_action_text') }} as latest_action_text,
        source_url
    from {{ source('govinfo_billstatus', 'related_bills') }}
),

keyed as (
    select
        bill_id,
        position,
        related_congress,
        related_bill_type,
        related_number,
        {{ dbt.safe_cast('related_congress', dbt.type_string()) }} || '-' || related_bill_type || '-'
        || {{ dbt.safe_cast('related_number', dbt.type_string()) }} as related_bill_id,
        title,
        latest_action_date,
        latest_action_text,
        source_url
    from src
)

select *
from keyed
where related_bill_id <> bill_id
