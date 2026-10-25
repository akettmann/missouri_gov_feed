-- A streak counts qualifying yearly periods, so it can't be longer than the number of yearly periods loaded,
-- and only yearly rows have one (lifetime rows must have none, yearly rows at least 1).
with yearly_periods as (
    select count(distinct period) as n
    from {{ ref('rpt_awards') }}
    where period <> 'lifetime'
)

select
    a.award,
    a.office,
    a.period,
    a.official_id,
    a.streak_years
from {{ ref('rpt_awards') }} as a
cross join yearly_periods as y
where
    (a.period = 'lifetime' and a.streak_years is not null)
    or (a.period <> 'lifetime' and (a.streak_years is null or a.streak_years < 1 or a.streak_years > y.n))
