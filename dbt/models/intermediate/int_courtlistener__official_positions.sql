-- Career positions from CourtListener's judge database for officials it covers
-- (matching in int_courtlistener__official_people).
select
    m.official_id,
    coalesce(nullif(pos.job_title, ''), c.full_name, pos.position_type) as position_title,
    coalesce(nullif(pos.organization_name, ''), c.full_name) as organization,
    {{ dbt.safe_cast('pos.date_start', 'date') }} as start_date,
    {{ dbt.safe_cast('pos.date_termination', 'date') }} as end_date,
    pos.how_selected
from {{ ref('int_courtlistener__official_people') }} as m
inner join {{ source('raw', 'cl_positions') }} as pos on m.cl_person_id = pos.person_id
left join {{ source('raw', 'cl_courts') }} as c on pos.court_id = c.id
