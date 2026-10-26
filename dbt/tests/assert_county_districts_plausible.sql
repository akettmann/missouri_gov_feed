-- Each county is covered by its state house, state senate and congressional districts, which partition the
-- state: the shares of the county they hold add up to about 1 for each type (a little under, as slivers under
-- 0.1 km2 are dropped; a little over or under from the planar area approximation). A county missing a type, or a
-- type whose shares are far from 1, means a vintage mix-up or a broken intersection.
with per_type as (
    select
        c.district_id as county_id,
        t.district_type,
        coalesce(sum(f.share_of_county), 0) as covered
    from {{ ref('dim_district') }} as c
    cross join (
        select 'state_house' as district_type
        union all
        select 'state_senate'
        union all
        select 'us_house'
    ) as t
    left join {{ ref('fct_county_districts') }} as f
        on c.district_id = f.county_id and t.district_type = f.district_type
    where
        c.district_type = 'county'
        and c.is_current
    group by c.district_id, t.district_type
)

select *
from per_type
where covered not between 0.98 and 1.02
