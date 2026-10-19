-- CourtListener judge database: one row per position a person held (judgeships and prior careers).
select
    person_id as cl_person_id,
    court_id,
    position_type,
    job_title,
    organization_name,
    how_selected,
    {{ dbt.safe_cast('date_start', 'date') }} as start_date,
    {{ dbt.safe_cast('date_termination', 'date') }} as end_date
from {{ source('raw', 'cl_positions') }}
