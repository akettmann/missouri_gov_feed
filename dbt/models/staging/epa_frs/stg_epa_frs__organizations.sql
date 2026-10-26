-- One row per organization affiliated with an EPA FRS facility through one program record: owner, operator,
-- parent company, contacts... org_type is mostly UNKNOWN; PRIVATE, MUNICIPAL, STATE, FEDERAL, DISTRICT and
-- COUNTY are the common known values. Malformed CSV rows (no REGISTRY_ID) are left out.
-- A name that still has U+FFFD (EPA lost a letter) is taken from the epa_frs_name_corrections seed if it has
-- a row, else from the one alternative name of the same registry id and program record that equals it with
-- each run of U+FFFD standing for one character; failing both, the U+FFFD is dropped. The name has runs of
-- whitespace collapsed and stray leading/trailing commas, semicolons and spaces cut (#319); the HTML entities EPA
-- leaves in it (&AMP;) are decoded (#398).
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
),

-- one alternative name matches the damaged pattern; two different matches are ambiguous and repair nothing
alt_repairs as (
    select
        src.registry_id,
        src.program_system,
        src.program_id,
        src.org_name,
        min(alt.alt_name) as repaired_name
    from src
    inner join {{ ref('stg_epa_frs__alt_names') }} as alt
        on
            src.registry_id = alt.registry_id
            and src.program_system = alt.program_system
            and src.program_id = alt.program_id
    where
        src.org_name like '%�%'
        and alt.alt_name not like '%�%'
        and alt.alt_name like {{ mogov.damaged_name_pattern('src.org_name') }} escape '!'
    group by src.registry_id, src.program_system, src.program_id, src.org_name
    having count(distinct alt.alt_name) = 1
)

select
    src.registry_id,
    src.program_system,
    src.program_id,
    upper(src.affiliation_type) as affiliation_type,
    {{ mogov.clean_registry_text(
        mogov.fix_replacement_char('src.org_name', 'coalesce(fixes.corrected_value, alt_repairs.repaired_name)')
    ) }} as org_name,
    upper(nullif(src.org_type, '')) as org_type,
    nullif(src.org_city, '') as org_city,
    nullif(src.org_state, '') as org_state,
    src.source_url
from src
left join fixes
    on src.registry_id || '|' || src.program_system || '|' || src.program_id = fixes.record_key
left join alt_repairs
    on
        src.registry_id = alt_repairs.registry_id
        and src.program_system = alt_repairs.program_system
        and src.program_id = alt_repairs.program_id
        and src.org_name = alt_repairs.org_name
where src.registry_id is not null
