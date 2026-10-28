-- Amendments filed to federal bills in the GovInfo BILLSTATUS bulk XML (loaded Congresses, all states), one row per
-- amendment. amendment_id has the form of bill_id ("118-hamdt-180", "118-samdt-999"); amendment_type is lower case
-- (hamdt, samdt) and chamber is the chamber the amendment belongs to as published ("House of Representatives",
-- "Senate"). bill_id is the bill the amendment was filed to and joins stg_govinfo_billstatus__bills;
-- amended_bill_id is the same bill as the amendment itself names it (the two agree for every amendment loaded).
-- When an amendment amends another amendment, amended_amendment_id names that one. Senate amendments carry
-- proposed_date; House ones submitted_date only. Purpose and description are free text as published and are often
-- missing (the House writes a description, the Senate a purpose). Sponsors are in
-- stg_govinfo_billstatus__amendment_sponsors, actions and roll calls in the two models after it.
with src as (
    select
        {{ mogov.json_str('payload', '$.amendment_id') }} as amendment_id,
        {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.congress'), dbt.type_int()) }} as congress,
        lower({{ mogov.json_str('payload', '$.amendment_type') }}) as amendment_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.number'), dbt.type_int()) }} as amendment_number,
        {{ mogov.json_str('payload', '$.chamber') }} as chamber,
        {{ mogov.json_str('payload', '$.description') }} as description,
        {{ mogov.json_str('payload', '$.purpose') }} as purpose,
        {{ dbt.safe_cast("substring(" ~ mogov.json_str('payload', '$.submitted_date') ~ ", 1, 10)", 'date') }}
            as submitted_date,
        {{ dbt.safe_cast("substring(" ~ mogov.json_str('payload', '$.proposed_date') ~ ", 1, 10)", 'date') }}
            as proposed_date,
        {{ dbt.safe_cast("substring(" ~ mogov.json_str('payload', '$.update_date') ~ ", 1, 10)", 'date') }}
            as update_date,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.latest_action_date'), 'date') }} as latest_action_date,
        {{ mogov.json_str('payload', '$.latest_action_text') }} as latest_action_text,
        {{ mogov.json_str('payload', '$.amended_bill_congress') }} as amended_bill_congress,
        {{ mogov.json_str('payload', '$.amended_bill_type') }} as amended_bill_type,
        {{ mogov.json_str('payload', '$.amended_bill_number') }} as amended_bill_number,
        {{ mogov.json_str('payload', '$.amended_amendment_congress') }} as amended_amendment_congress,
        {{ mogov.json_str('payload', '$.amended_amendment_type') }} as amended_amendment_type,
        {{ mogov.json_str('payload', '$.amended_amendment_number') }} as amended_amendment_number,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.amendments_to_amendment_count'), dbt.type_int()) }}
            as amendments_to_amendment_count,
        source_url
    from {{ source('govinfo_billstatus', 'amendments') }}
)

select
    amendment_id,
    bill_id,
    congress,
    amendment_type,
    amendment_number,
    chamber,
    description,
    purpose,
    submitted_date,
    proposed_date,
    update_date,
    latest_action_date,
    latest_action_text,
    {{ mogov.billstatus_related_bill_id('amended_bill_congress', 'amended_bill_type', 'amended_bill_number') }}
        as amended_bill_id,
    case
        when amended_amendment_number is not null
            then {{ mogov.billstatus_related_bill_id(
                'amended_amendment_congress', 'amended_amendment_type', 'amended_amendment_number') }}
    end as amended_amendment_id,
    amendments_to_amendment_count,
    source_url
from src
