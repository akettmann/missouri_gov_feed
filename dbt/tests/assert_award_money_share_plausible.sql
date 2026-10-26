-- Sanity checks on least_committee_money_share, which is a percentage of all money raised:
--   * never above 100 (committee money can't exceed the total it is part of);
--   * a ranked field (awards_min_field_size or more officials) must not have every member at 100.0: that is a
--     numerator/denominator drawn from different money (issue 188: federal rows once held committee money
--     only, so all U.S. House members read 100%). Real fields spread out. Fields tied at 0.0 are allowed:
--     many state members really have no PAC money (tied ranks are a separate, known issue).
with shares as (
    select
        office,
        period,
        official_id,
        metric
    from {{ ref('rpt_awards') }}
    where award = 'least_committee_money_share'
),

fields as (
    select
        office,
        period,
        count(*) as members,
        min(metric) as lowest,
        max(metric) as highest
    from shares
    group by office, period
)

select
    office,
    period,
    members,
    lowest,
    highest
from fields
where
    highest > 100
    or lowest < 0
    or (members >= {{ var('awards_min_field_size') }} and lowest = highest and highest = 100)
