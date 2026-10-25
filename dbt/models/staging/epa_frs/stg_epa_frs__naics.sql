-- One row per NAICS code an EPA FRS program record gives a facility. is_primary marks the program's primary
-- code (PRIMARY_INDICATOR); is_secondary the ones FRS calls SECONDARY; the rest are UNKNOWN. A facility can have
-- several programs and so several codes. Malformed CSV rows (no REGISTRY_ID) are left out.
select
    {{ mogov.json_str('payload', '$.REGISTRY_ID') }} as registry_id,
    {{ mogov.json_str('payload', '$.PGM_SYS_ACRNM') }} as program_system,
    {{ mogov.json_str('payload', '$.NAICS_CODE') }} as naics_code,
    trim({{ mogov.json_str('payload', '$.CODE_DESCRIPTION') }}) as naics_description,
    coalesce(upper({{ mogov.json_str('payload', '$.PRIMARY_INDICATOR') }}) = 'PRIMARY', false) as is_primary,
    coalesce(upper({{ mogov.json_str('payload', '$.PRIMARY_INDICATOR') }}) = 'SECONDARY', false) as is_secondary,
    source_url
from {{ source('epa_frs', 'naics') }}
where {{ mogov.json_str('payload', '$.REGISTRY_ID') }} is not null
