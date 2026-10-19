-- CourtListener courts: id and full name.
select
    id as court_id,
    full_name as court_name
from {{ source('raw', 'cl_courts') }}
