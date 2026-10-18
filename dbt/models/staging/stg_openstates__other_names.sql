-- Alternate spellings Open States has seen for each person; used to match people in other sources.
select
    openstates_id,
    full_name,
    full_name as alt_name
from {{ ref('stg_openstates__people') }}

union

select
    p.openstates_id,
    p.full_name,
    {{ mogov.json_str('n.value', '$.name') }} as alt_name
from {{ ref('stg_openstates__people') }} as p
cross join lateral {{ mogov.json_elements('p.doc', '$.other_names') }} as n
