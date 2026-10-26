-- EPA FRS text is decoded in staging (#398): no name, address or city may still hold an HTML entity such as
-- "&AMP;" or "&#39;". The pattern matches known entity shapes only (case-sensitive, so each case is listed), so
-- text like "AT&T;" is not flagged. A row here: check the match is really an entity, then add it to
-- mogov.decode_registry_entities and to the pattern below.
{% set entity = '&(#[0-9]{1,5}|amp|AMP|quot|QUOT|lt|LT|gt|GT|apos|nbsp|NBSP);' %}

select
    'facilities' as model,
    registry_id,
    facility_name || ' | ' || coalesce(address, '') || ' | ' || coalesce(city, '') as text_value
from {{ ref('stg_epa_frs__facilities') }}
where
    {{ mogov.regex_matches('facility_name', entity) }}
    or {{ mogov.regex_matches('address', entity) }}
    or {{ mogov.regex_matches('city', entity) }}

union all

select
    'organizations' as model,
    registry_id,
    org_name as text_value
from {{ ref('stg_epa_frs__organizations') }}
where {{ mogov.regex_matches('org_name', entity) }}
