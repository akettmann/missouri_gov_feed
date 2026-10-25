-- Every epa_frs_name_corrections row must match at least one staged row (by its record_key), otherwise it silently
-- does nothing; any row returned is a failure. The seed may be empty.
with staged as (
    select
        registry_id as record_key,
        'facility_name' as field
    from {{ ref('stg_epa_frs__facilities') }}
    union all
    select
        registry_id || '|' || program_system || '|' || program_id as record_key,
        'org_name' as field
    from {{ ref('stg_epa_frs__organizations') }}
)

select
    fixes.record_key,
    fixes.field
from {{ ref('epa_frs_name_corrections') }} as fixes
left join staged on fixes.record_key = staged.record_key and fixes.field = staged.field
where staged.record_key is null
