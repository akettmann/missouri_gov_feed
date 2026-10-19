-- Every FEC candidate ID a Missouri member of Congress has used (House and Senate runs get separate IDs).
select
    l.bioguide_id,
    {{ mogov.json_str('f.value', '$') }} as fec_candidate_id
from {{ ref('stg_congress__legislators') }} as l
cross join lateral {{ mogov.json_elements('l.p', '$.id.fec') }} as f
