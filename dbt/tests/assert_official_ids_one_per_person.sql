-- No two official_ids may be one person (#97). Two ids sharing an exact full name whose office history overlaps -- they
-- hold the same office and district, or any office in the same year -- are the same person under two ids (the House
-- roster and Open States keyed them differently, or Open States holds the person twice), unless a maintainer has
-- reviewed the pair as different people in official_id_links (relation different_people, signed off: checked_by and
-- checked_on filled, as int_officials__person_ids requires).
-- Covers everyone int_officeholders__years lists for a past year, plus every current official as of the latest year.
with latest as (
    select max(year) as year from {{ ref('int_officeholders__years') }}
),

holdings as (
    select distinct
        official_id,
        full_name,
        year,
        office,
        district
    from {{ ref('int_officeholders__years') }}
    union
    select
        c.official_id,
        c.full_name,
        l.year,
        c.office,
        c.district
    from {{ ref('int_officials__current') }} as c
    cross join latest as l
),

reviewed as (
    select
        alias_id,
        person_id
    from {{ ref('official_id_links') }}
    where relation = 'different_people' and checked_by is not null and checked_on is not null
)

select
    a.full_name,
    a.official_id as official_id_a,
    b.official_id as official_id_b,
    min(a.office) as office,
    min(a.year) as year
from holdings as a
inner join holdings as b
    on
        lower(trim(a.full_name)) = lower(trim(b.full_name))
        and a.official_id < b.official_id
        and (
            a.year = b.year
            or (a.office = b.office and coalesce(a.district, '') = coalesce(b.district, ''))
        )
left join reviewed as r
    on
        (a.official_id = r.alias_id and b.official_id = r.person_id)
        or (b.official_id = r.alias_id and a.official_id = r.person_id)
where r.alias_id is null
group by a.full_name, a.official_id, b.official_id
