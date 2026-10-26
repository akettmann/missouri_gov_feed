-- The 24-hour-notice dedupe (#156) may only drop "24 Hour" notice rows, and never more than half of the notice
-- dollars. Returns every dropped non-notice row, and one summary row if the dropped dollars are implausible
-- (measured October 2026: 127 rows, 6% of notice dollars).
with dropped as (
    select
        s.record_id,
        s.report,
        s.amount
    from {{ ref('stg_tap_mec__contributions') }} as s
    where not exists (
        select 1
        from {{ ref('int_tap_mec__contributions') }} as k
        where k.record_id = s.record_id
    )
),

notice_dollars as (
    select sum(n.amount) as total
    from {{ ref('stg_tap_mec__contributions') }} as n
    where lower(n.report) like '%24 hour%'
),

dropped_dollars as (
    select sum(d.amount) as total
    from dropped as d
)

select
    d.record_id,
    d.report,
    d.amount
from dropped as d
where coalesce(lower(d.report) not like '%24 hour%', true)
union all
select
    'dropped more than half of the notice dollars' as record_id,
    null as report,
    dd.total as amount
from dropped_dollars as dd
cross join notice_dollars as nd
where dd.total > nd.total * 0.5
