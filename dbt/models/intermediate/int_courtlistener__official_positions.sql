-- Career positions from CourtListener's judge database for officials it covers: federal judges by FJC id,
-- state judges by exact first+last name among people who held a Missouri court seat.
with mo_people as (
    select distinct person_id
    from {{ source('raw', 'cl_positions') }}
    where court_id in ('mo', 'moctapp', 'moctapped', 'moctappwd', 'moctappsd', 'moed', 'mowd', 'ca8')
),

people as (
    select
        p.id as cl_person_id,
        p.fjc_id,
        {{ mogov.name_key("p.name_first || ' ' || p.name_last") }} as name_key
    from {{ source('raw', 'cl_people') }} as p
    inner join mo_people as m on p.id = m.person_id
),

by_fjc as (
    select
        j.official_id,
        p.cl_person_id
    from {{ ref('int_judges__federal') }} as j
    inner join {{ ref('stg_fjc__appointments') }} as a on j.fjc_nid = a.fjc_nid and a.appointment_number = 1
    inner join people as p on a.fjc_jid = p.fjc_id
),

by_name as (
    select
        o.official_id,
        max(p.cl_person_id) as cl_person_id
    from {{ ref('int_officials__current') }} as o
    inner join people as p
        on {{ mogov.name_key(dbt.split_part('o.given_name', "' '", 1) ~ " || ' ' || o.family_name") }} = p.name_key
    where o.office in ('mo_supreme_court', 'mo_court_of_appeals', 'mo_circuit_judge', 'mo_associate_circuit_judge')
    group by 1
    having count(distinct p.cl_person_id) = 1
),

matched as (
    select * from by_fjc
    union
    select * from by_name
)

select
    m.official_id,
    coalesce(nullif(pos.job_title, ''), c.full_name, pos.position_type) as position_title,
    coalesce(nullif(pos.organization_name, ''), c.full_name) as organization,
    {{ dbt.safe_cast('pos.date_start', 'date') }} as start_date,
    {{ dbt.safe_cast('pos.date_termination', 'date') }} as end_date,
    pos.how_selected
from matched as m
inner join {{ source('raw', 'cl_positions') }} as pos on m.cl_person_id = pos.person_id
left join {{ source('raw', 'cl_courts') }} as c on pos.court_id = c.id
