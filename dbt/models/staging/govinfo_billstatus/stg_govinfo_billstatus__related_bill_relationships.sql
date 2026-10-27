-- How a federal bill relates to one of its related bills, from the GovInfo BILLSTATUS bulk XML: one row per
-- (bill, related bill, relationship). relationship_type is as published ("Identical bill", "Related bill",
-- "Procedurally related", ...) and identified_by says who made the link (CRS, or the House or Senate itself).
-- related_position is the position of the row in stg_govinfo_billstatus__related_bills. relationship_type_normalized
-- is lower case with hyphens as spaces ("Procedurally-related" = "Procedurally related"); filter on it. CRS
-- sometimes lists a bill as related to itself; those rows are dropped here and in the related bills model, so
-- related_position gaps are expected.
with src as (
    select
        {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.related_position'), dbt.type_int()) }} as related_position,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as position,
        {{ mogov.json_str('payload', '$.relationship_type') }} as relationship_type,
        {{ mogov.billstatus_label_normalized(mogov.json_str('payload', '$.relationship_type')) }}
            as relationship_type_normalized,
        {{ mogov.json_str('payload', '$.identified_by') }} as identified_by,
        source_url
    from {{ source('govinfo_billstatus', 'related_bill_relationships') }}
),

self_relations as (
    select
        {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.position'), dbt.type_int()) }} as related_position
    from {{ source('govinfo_billstatus', 'related_bills') }}
    where
        {{ mogov.billstatus_related_bill_id(
            mogov.json_str('payload', '$.related_congress'),
            mogov.json_str('payload', '$.related_bill_type'),
            mogov.json_str('payload', '$.related_number')) }}
        = {{ mogov.json_str('payload', '$.bill_id') }}
)

select
    src.bill_id,
    src.related_position,
    src.position,
    src.relationship_type,
    src.relationship_type_normalized,
    src.identified_by,
    src.source_url
from src
left join self_relations
    on src.bill_id = self_relations.bill_id and src.related_position = self_relations.related_position
where self_relations.bill_id is null
