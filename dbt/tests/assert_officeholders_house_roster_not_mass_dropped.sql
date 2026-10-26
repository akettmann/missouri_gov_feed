-- Sanity check: the House has 163 seats and every roster year here lists 154 or more members (the lowest, 2022,
-- is 154). Fewer than 150 in a year means rows were dropped wholesale, e.g. the last-vote test emptying the
-- newest year in January before that year's roll calls are loaded (#491). Years come from the roster, so a year
-- with no rows at all is counted as 0, not skipped.
with roster_years as (
    select distinct session_year as year
    from {{ ref('int_mo_house__member_identity') }}
),

kept as (
    select
        year,
        count(*) as house_rows
    from {{ ref('int_officeholders__years') }}
    where office = 'state_house'
    group by year
)

select
    r.year,
    coalesce(k.house_rows, 0) as house_rows
from roster_years as r
left join kept as k on r.year = k.year
where coalesce(k.house_rows, 0) < 150
