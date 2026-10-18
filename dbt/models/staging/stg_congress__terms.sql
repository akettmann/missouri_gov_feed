-- One row per congressional term served (any state), for MO members' past-office history.
select
    l.bioguide_id,
    l.full_name,
    {{ mogov.json_str('t.value', '$.type') }} as term_type,   -- rep | sen
    {{ mogov.json_str('t.value', '$.state') }} as state,
    {{ mogov.json_str('t.value', '$.district') }} as district,
    {{ mogov.json_str('t.value', '$.party') }} as party,
    {{ dbt.safe_cast(mogov.json_str('t.value', '$.start'), 'date') }} as start_date,
    {{ dbt.safe_cast(mogov.json_str('t.value', '$.end'), 'date') }} as end_date
from {{ ref('stg_congress__legislators') }} as l
cross join lateral {{ mogov.json_elements('l.p', '$.terms') }} as t
