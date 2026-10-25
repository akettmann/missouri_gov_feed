-- One row per alternative name an EPA FRS program record gives a facility (MO_ALTERNATIVE_NAME_FILE): the program
-- system's own spelling of the site name. EPA pads some names with trailing spaces; alt_name is trimmed. Staging
-- of facilities and organizations uses these to repair names where EPA's file lost a letter to U+FFFD. Malformed
-- CSV rows (no REGISTRY_ID) and blank names are left out.
with src as (
    select
        {{ mogov.json_str('payload', '$.REGISTRY_ID') }} as registry_id,
        {{ mogov.json_str('payload', '$.PGM_SYS_ACRNM') }} as program_system,
        {{ mogov.json_str('payload', '$.PGM_SYS_ID') }} as program_id,
        trim({{ mogov.json_str('payload', '$.ALTERNATIVE_NAME') }}) as alt_name,
        {{ mogov.json_str('payload', '$.ALTERNATIVE_NAME_TYPE') }} as alt_name_type,
        source_url
    from {{ source('epa_frs', 'alt_names') }}
)

select
    registry_id,
    program_system,
    program_id,
    alt_name,
    alt_name_type,
    source_url
from src
where registry_id is not null and alt_name != ''
