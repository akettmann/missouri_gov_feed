{{ config(enabled=var('cl_case_bulk', false)) }}
-- Federal district-court dockets (E.D. and W.D. Missouri) that have an assigned judge: filed and terminated
-- dates (null when the docket has none) and the days between. A docket whose termination date is before its
-- filing date has a negative duration (a source error): it is kept and flagged with ends_before_filed, and the
-- judge metric leaves it out. The state courts carry no judge or dates in the bulk export, so only the federal
-- districts are here.
select
    docket_id,
    court_id,
    assigned_to_person_id as cl_person_id,
    date_filed,
    date_terminated,
    date_filed is not null and date_terminated is not null as has_both_dates,
    {{ dbt.datediff('date_filed', 'date_terminated', 'day') }} as days_to_disposition,
    date_terminated < date_filed as ends_before_filed
from {{ ref('stg_courtlistener__mo_dockets') }}
where
    court_id in ('moed', 'mowd')
    and assigned_to_person_id is not null
