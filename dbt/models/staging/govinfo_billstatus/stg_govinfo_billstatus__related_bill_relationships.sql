-- How a federal bill relates to one of its related bills, from the GovInfo BILLSTATUS bulk XML: one row per
-- (bill, related bill, relationship). relationship_type is as published ("Identical bill", "Related bill",
-- "Procedurally related", ...) and identified_by says who made the link (CRS, or the House or Senate itself).
-- related_position is the position of the row in stg_govinfo_billstatus__related_bills.
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.related_position'), dbt.type_int()) }} as related_position,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
    {{ mogov.json_str('payload', '$.relationship_type') }} as relationship_type,
    {{ mogov.json_str('payload', '$.identified_by') }} as identified_by,
    source_url
from {{ source('govinfo_billstatus', 'related_bill_relationships') }}
