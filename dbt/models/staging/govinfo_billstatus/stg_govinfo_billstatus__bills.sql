-- Federal bills from the GovInfo BILLSTATUS bulk XML (loaded Congresses, all states), one row per bill. bill_type is
-- lower-case (hr, s, hjres, sjres, hconres, sconres, hres, sres). The latest action is the text as published; whether
-- a bill became law is read from the actions (int_federal_bills__stage), never from this text. Only about a third
-- of the files carry their congress.gov link, so the rest get it built from the type, congress and number
-- (https://www.congress.gov/bill/118th-congress/house-joint-resolution/7), which is the form the files use.
with src as (
    select
        {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.congress'), dbt.type_int()) }} as congress,
        lower({{ mogov.json_str('payload', '$.bill_type') }}) as bill_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.number'), dbt.type_int()) }} as bill_number,
        {{ mogov.json_str('payload', '$.origin_chamber') }} as origin_chamber,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.introduced_date'), 'date') }} as introduced_date,
        {{ dbt.safe_cast("substring(" ~ mogov.json_str('payload', '$.update_date') ~ ", 1, 10)", 'date') }}
            as update_date,
        {{ mogov.json_str('payload', '$.title') }} as title,
        {{ mogov.json_str('payload', '$.policy_area') }} as policy_area,
        {{ mogov.json_str('payload', '$.legislation_url') }} as published_url,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.latest_action_date'), 'date') }} as latest_action_date,
        {{ mogov.json_str('payload', '$.latest_action_text') }} as latest_action_text,
        source_url
    from {{ source('govinfo_billstatus', 'bills') }}
)

select
    bill_id,
    congress,
    bill_type,
    bill_number,
    origin_chamber,
    introduced_date,
    update_date,
    title,
    policy_area,
    coalesce(
        published_url,
        'https://www.congress.gov/bill/' || {{ mogov.ordinal('congress') }} || '-congress/'
        || case bill_type
            when 'hr' then 'house-bill'
            when 's' then 'senate-bill'
            when 'hjres' then 'house-joint-resolution'
            when 'sjres' then 'senate-joint-resolution'
            when 'hconres' then 'house-concurrent-resolution'
            when 'sconres' then 'senate-concurrent-resolution'
            when 'hres' then 'house-resolution'
            when 'sres' then 'senate-resolution'
        end
        || '/' || {{ dbt.safe_cast('bill_number', dbt.type_string()) }}
    ) as legislation_url,
    latest_action_date,
    latest_action_text,
    source_url
from src
