-- Officials matched to people in CourtListener's judge database: federal judges by FJC id (falling back, for
-- CourtListener people with no fjc_id, to exact first+last name + same court + judgeship start equal to the FJC
-- commission date, only when that pairs exactly one judge with exactly one person), state judges by exact
-- first+last name among people who held a seat on a tracked court (only when the name is unambiguous).
with mo_people as (
    select distinct pos.cl_person_id
    from {{ ref('stg_courtlistener__positions') }} as pos
    inner join {{ ref('mo_courts') }} as c on pos.court_id = c.court_id
),

people as (
    select
        p.cl_person_id,
        p.fjc_id,
        {{ mogov.name_key("p.name_first || ' ' || p.name_last") }} as name_key
    from {{ ref('stg_courtlistener__people') }} as p
    inner join mo_people as m on p.cl_person_id = m.cl_person_id
),

by_fjc as (
    select
        j.official_id,
        p.cl_person_id
    from {{ ref('int_judges__federal') }} as j
    inner join {{ ref('stg_fjc__appointments') }} as a on j.fjc_nid = a.fjc_nid and a.appointment_number = 1
    inner join people as p on a.fjc_jid = p.fjc_id
),

fjc_commissions as (
    select
        j.official_id,
        {{ mogov.name_key("a.given_name || ' ' || a.family_name") }} as name_key,
        case a.court_name
            when 'U.S. District Court for the Eastern District of Missouri' then 'moed'
            when 'U.S. District Court for the Western District of Missouri' then 'mowd'
            when 'U.S. Court of Appeals for the Eighth Circuit' then 'ca8'
        end as court_id,
        a.commission_date
    from {{ ref('int_judges__federal') }} as j
    inner join {{ ref('stg_fjc__appointments') }} as a on j.fjc_nid = a.fjc_nid
    where j.official_id not in (select b.official_id from by_fjc as b)
),

-- CourtListener people that carry no FJC id of their own (so by_fjc could never reach them) and are not
-- already claimed by an FJC id match.
unkeyed_starts as (
    select
        p.cl_person_id,
        p.name_key,
        pos.court_id,
        pos.start_date
    from people as p
    inner join {{ ref('stg_courtlistener__positions') }} as pos on p.cl_person_id = pos.cl_person_id
    where
        p.fjc_id is null
        and pos.position_type = 'jud'
        and p.cl_person_id not in (select b.cl_person_id from by_fjc as b)
),

by_commission as (
    select
        f.official_id,
        u.cl_person_id
    from fjc_commissions as f
    inner join unkeyed_starts as u
        on
            f.name_key = u.name_key
            and f.court_id = u.court_id
            and f.commission_date = u.start_date
    group by 1, 2
),

-- Never link two officials to one person or one official to two people.
by_commission_unique as (
    select
        official_id,
        cl_person_id
    from (
        select
            c.official_id,
            c.cl_person_id,
            count(*) over (partition by c.official_id) as people_per_official,
            count(*) over (partition by c.cl_person_id) as officials_per_person
        from by_commission as c
    ) as counted
    where people_per_official = 1 and officials_per_person = 1
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
)

select * from by_fjc
union
select * from by_commission_unique
union
select * from by_name
