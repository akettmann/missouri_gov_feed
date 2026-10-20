-- One row per organization affiliated with an EPA FRS facility through one program record: owner, operator,
-- parent company, contacts... org_type is mostly UNKNOWN; PRIVATE, MUNICIPAL, STATE, FEDERAL, DISTRICT and
-- COUNTY are the common known values. Malformed CSV rows (no REGISTRY_ID) are left out.
select
    {{ mogov.json_str('payload', '$.REGISTRY_ID') }} as registry_id,
    {{ mogov.json_str('payload', '$.PGM_SYS_ACRNM') }} as program_system,
    {{ mogov.json_str('payload', '$.PGM_SYS_ID') }} as program_id,
    upper({{ mogov.json_str('payload', '$.AFFILIATION_TYPE') }}) as affiliation_type,
    {{ mogov.json_str('payload', '$.ORG_NAME') }} as org_name,
    upper(nullif({{ mogov.json_str('payload', '$.ORG_TYPE') }}, '')) as org_type,
    nullif({{ mogov.json_str('payload', '$.CITY_NAME') }}, '') as org_city,
    nullif({{ mogov.json_str('payload', '$.STATE_CODE') }}, '') as org_state,
    source_url
from {{ source('epa_frs', 'organizations') }}
where {{ mogov.json_str('payload', '$.REGISTRY_ID') }} is not null
