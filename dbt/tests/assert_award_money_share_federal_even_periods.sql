-- Federal money shares are ranked per two-year FEC cycle, named by the even end year (or 'lifetime'). An odd
-- period means a federal share ranked per calendar year slipped back in (or a stale build); the frontend words
-- these periods as "2024-25 cycle" and would mislabel them. "Federal" is rpt_awards' own definition
-- (level = 'federal'), joined through the officials dimension rather than a hardcoded office list.
select
    a.award,
    a.office,
    a.period,
    a.official_id
from {{ ref('rpt_awards') }} as a
inner join {{ ref('dim_official') }} as o on a.official_id = o.official_id
where
    a.award = 'least_committee_money_share'
    and o.level = 'federal'
    and case when a.period <> 'lifetime' then cast(a.period as integer) end % 2 <> 0
