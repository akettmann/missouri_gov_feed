-- Career positions from CourtListener's judge database for officials it covers
-- (matching in int_courtlistener__official_people).
select
    m.official_id,
    coalesce(nullif(pos.job_title, ''), c.court_name, pos.position_type) as position_title,
    coalesce(nullif(pos.organization_name, ''), c.court_name) as organization,
    pos.start_date,
    pos.end_date,
    pos.how_selected
from {{ ref('int_courtlistener__official_people') }} as m
inner join {{ ref('stg_courtlistener__positions') }} as pos on m.cl_person_id = pos.cl_person_id
left join {{ ref('stg_courtlistener__courts') }} as c on pos.court_id = c.court_id
