-- Every role (office) each Open States person has held: the state-level past-offices history.
select
    p.openstates_id,
    p.full_name,
    {{ mogov.json_str('r.value', '$.type') }} as role_type,
    {{ mogov.json_str('r.value', '$.district') }} as district,
    {{ mogov.json_str('r.value', '$.jurisdiction') }} as jurisdiction,
    {{ dbt.safe_cast(mogov.json_str('r.value', '$.start_date'), 'date') }} as start_date,
    {{ dbt.safe_cast(mogov.json_str('r.value', '$.end_date'), 'date') }} as end_date,
    {{ mogov.json_str('r.value', '$.end_reason') }} as end_reason
from {{ ref('stg_openstates__people') }} as p
cross join lateral {{ mogov.json_elements('p.doc', '$.roles') }} as r
