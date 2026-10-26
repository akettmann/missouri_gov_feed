-- period_kind = 'fec_cycle' rows are two-year FEC cycles named by the even end year (the frontend words them as
-- "2024-25 cycle"), so an odd period there means a calendar-year row slipped in. And every non-lifetime federal
-- money-share row must be a cycle: a federal share ranked per calendar year (the rollup holds only committee
-- receipts, so it would read 100%) must not come back. "Federal" is rpt_awards' own definition (level =
-- 'federal'), joined through the officials dimension rather than a hardcoded office list. The reverse holds
-- too: the only fec_cycle rows are federal least_committee_money_share (the frontend words every one of them
-- as an FEC cycle).
select
    a.award,
    a.office,
    a.period,
    a.period_kind,
    a.official_id
from {{ ref('rpt_awards') }} as a
inner join {{ ref('dim_official') }} as o on a.official_id = o.official_id
where
    (a.period_kind = 'fec_cycle' and cast(a.period as integer) % 2 <> 0)
    or (
        a.period_kind = 'fec_cycle'
        and (a.award <> 'least_committee_money_share' or o.level <> 'federal')
    )
    or (
        a.award = 'least_committee_money_share'
        and o.level = 'federal'
        and a.period_kind not in ('fec_cycle', 'lifetime')
    )
