{{ config(enabled=var('cl_case_bulk', false)) }}
-- CourtListener bulk dockets in tracked Missouri state and federal courts (filtered by the loader), with the
-- assigned judge's CourtListener person id and the filing and termination dates (null when the docket has none).
select
    id as docket_id,
    court_id,
    case_name,
    docket_number,
    assigned_to_id as assigned_to_person_id,
    {{ dbt.safe_cast('date_filed', 'date') }} as date_filed,
    {{ dbt.safe_cast('date_terminated', 'date') }} as date_terminated
from {{ source('courtlistener', 'mo_dockets') }}
