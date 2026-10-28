-- Free text of the BILLSTATUS amendment models (#738) must come through clean: no HTML entity, no U+FFFD replacement
-- character, no filler value ('~', 'NONE', 'N/A', 'UNKNOWN' or a one-character value) and no doubled comma or
-- semicolon. The 118th Congress has none today; a row here means the source changed, so extend the shared cleaning
-- macros (dbt/macros/names.sql) in staging rather than patching the model.
{% set entity = '&(#[0-9]{1,5}|amp|AMP|quot|QUOT|lt|LT|gt|GT|apos|nbsp|NBSP);' %}
{% set doubled = '(,,|;;)' %}

with text_values as (
    select
        'purpose' as model,
        amendment_id,
        purpose as text_value
    from {{ ref('stg_govinfo_billstatus__amendments') }}
    union all
    select
        'description' as model,
        amendment_id,
        description as text_value
    from {{ ref('stg_govinfo_billstatus__amendments') }}
    union all
    select
        'latest_action_text' as model,
        amendment_id,
        latest_action_text as text_value
    from {{ ref('stg_govinfo_billstatus__amendments') }}
    union all
    select
        'sponsor_name' as model,
        amendment_id,
        name as text_value
    from {{ ref('stg_govinfo_billstatus__amendment_sponsors') }}
    union all
    select
        'action_text' as model,
        amendment_id,
        action_text as text_value
    from {{ ref('stg_govinfo_billstatus__amendment_actions') }}
)

select
    model,
    amendment_id,
    text_value
from text_values
where
    text_value like '%�%'
    or {{ mogov.regex_matches('text_value', entity) }}
    or {{ mogov.regex_matches('text_value', doubled) }}
    or upper(trim(text_value)) in ('~', 'NONE', 'N/A', 'NA', 'UNKNOWN', 'NULL')
    or length(trim(text_value)) = 1
