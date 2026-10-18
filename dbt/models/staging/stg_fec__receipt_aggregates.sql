-- FEC API: itemized individual receipts per principal committee, aggregated by employer / size / state.
-- Empty when FEC_API_KEY isn't configured.
select
    {{ mogov.json_str('payload', '$.candidate_id') }} as candidate_id,
    {{ mogov.json_str('payload', '$.committee_id') }} as committee_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.cycle'), dbt.type_int()) }} as cycle,
    {{ mogov.json_str('payload', '$.aggregate') }} as aggregate_kind,
    coalesce(
        {{ mogov.json_str('payload', '$.employer') }},
        {{ mogov.json_str('payload', '$.state_full') }},
        {{ mogov.json_str('payload', '$.size') }}
    ) as bucket,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.total'), dbt.type_numeric()) }} as total,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.count'), dbt.type_int()) }} as contribution_count
from {{ source('raw', 'fec_receipt_aggregates') }}
