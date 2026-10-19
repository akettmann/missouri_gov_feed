-- CourtListener judge database: one row per person (national; bulk export).
select
    id as cl_person_id,
    fjc_id,
    name_first,
    name_middle,
    name_last,
    name_suffix
from {{ source('courtlistener', 'people') }}
