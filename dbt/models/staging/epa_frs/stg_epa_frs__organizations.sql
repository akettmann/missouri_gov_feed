-- One row per organization affiliated with an EPA FRS facility through one program record: owner, operator,
-- parent company, contacts... org_type is mostly UNKNOWN; PRIVATE, MUNICIPAL, STATE, FEDERAL, DISTRICT and
-- COUNTY are the common known values. Malformed CSV rows (no REGISTRY_ID) are left out.
with src as (
    select
        {{ mogov.json_str('payload', '$.REGISTRY_ID') }} as registry_id,
        {{ mogov.json_str('payload', '$.PGM_SYS_ACRNM') }} as program_system,
        {{ mogov.json_str('payload', '$.PGM_SYS_ID') }} as program_id,
        {{ mogov.json_str('payload', '$.AFFILIATION_TYPE') }} as affiliation_type,
        {{ mogov.json_str('payload', '$.ORG_NAME') }} as org_name,
        {{ mogov.json_str('payload', '$.ORG_TYPE') }} as org_type,
        {{ mogov.json_str('payload', '$.CITY_NAME') }} as org_city,
        {{ mogov.json_str('payload', '$.STATE_CODE') }} as org_state,
        source_url
    from {{ source('epa_frs', 'organizations') }}
),

fixes as (
    select
        record_key,
        corrected_value
    from {{ ref('epa_frs_name_corrections') }}
    where field = 'org_name'
)

select
    src.registry_id,
    src.program_system,
    src.program_id,
    upper(src.affiliation_type) as affiliation_type,
    {{ mogov.fix_replacement_char('src.org_name', 'fixes.corrected_value') }} as org_name,
    upper(nullif(src.org_type, '')) as org_type,
    nullif(src.org_city, '') as org_city,
    nullif(src.org_state, '') as org_state,
    src.source_url
from src
left join fixes
    on src.registry_id || '|' || src.program_system || '|' || src.program_id = fixes.record_key
where src.registry_id is not null
