-- Free text of the BILLSTATUS committee, subject and related-bill models (#625) must come through clean: no HTML
-- entity, no U+FFFD replacement character, no filler value ('~', 'NONE', 'N/A', 'UNKNOWN' or a one-character name) and
-- no doubled comma or semicolon. The CRS vocabulary and committee names have none today; a row here means the source
-- changed, so extend the shared cleaning macros (dbt/macros/names.sql) rather than patching the model.
{% set entity = '&(#[0-9]{1,5}|amp|AMP|quot|QUOT|lt|LT|gt|GT|apos|nbsp|NBSP);' %}
{% set doubled = '(,,|;;)' %}

with text_values as (
    select
        'committees' as model,
        bill_id,
        name as text_value
    from {{ ref('stg_govinfo_billstatus__committees') }}
    union all
    select
        'subjects' as model,
        bill_id,
        subject as text_value
    from {{ ref('stg_govinfo_billstatus__subjects') }}
    union all
    select
        'related_bills' as model,
        bill_id,
        title as text_value
    from {{ ref('stg_govinfo_billstatus__related_bills') }}
    union all
    select
        'related_bills_latest_action' as model,
        bill_id,
        latest_action_text as text_value
    from {{ ref('stg_govinfo_billstatus__related_bills') }}
)

select
    model,
    bill_id,
    text_value
from text_values
where
    text_value like '%�%'
    or {{ mogov.regex_matches('text_value', entity) }}
    or {{ mogov.regex_matches('text_value', doubled) }}
    or upper(trim(text_value)) in ('~', 'NONE', 'N/A', 'NA', 'UNKNOWN', 'NULL')
    or length(trim(text_value)) = 1
