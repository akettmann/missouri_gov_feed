-- Golden check of the real seed mo_senate_action_flags (the unit tests mock it): each wording in the seed
-- mo_senate_action_flag_examples, as seen on senate.mo.gov, maps to exactly the stage flags listed there
-- (expected_flag `none` = counts for no stage). Substitute and amendment actions, the enrollment steps and the
-- Governor-message line must map to nothing, so the words "withdrawn", "defeated" and "adopted" on a substitute
-- never move a bill. Returns every mismatch; a new phrasing is a seed row, and a seed change that breaks one of
-- the examples fails here.
with examples as (
    select * from {{ ref('mo_senate_action_flag_examples') }}
),

actual as (
    select
        e.action,
        e.bill_type,
        coalesce(m.flag, 'none') as flag
    from (select distinct
        action,
        bill_type
    from examples) as e
    left join {{ ref('mo_senate_action_flags') }} as m
        on
            lower(e.action) like lower(m.action_pattern)
            and (m.bill_type = 'any' or e.bill_type = m.bill_type)
)

select
    coalesce(e.action, a.action) as action,
    coalesce(e.bill_type, a.bill_type) as bill_type,
    e.expected_flag,
    a.flag as actual_flag
from examples as e
full outer join actual as a
    on
        e.action = a.action
        and e.bill_type = a.bill_type
        and e.expected_flag = a.flag
where e.action is null or a.action is null
