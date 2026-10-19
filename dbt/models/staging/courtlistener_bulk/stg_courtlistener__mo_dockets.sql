{{ config(enabled=var('cl_case_bulk', false)) }}
-- CourtListener bulk dockets in tracked Missouri state and federal courts (filtered by the loader).
select
    id as docket_id,
    court_id,
    case_name,
    docket_number
from {{ source('raw', 'cl_mo_dockets') }}
