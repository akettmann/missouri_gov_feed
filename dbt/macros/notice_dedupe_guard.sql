{#- Guard for the 24-hour-notice dedupe (#156, #554), shared by the TAP and direct-export tests. stg is the staging
    relation (every source row), kept the model after drop_reitemized_notices. Returns one row for each dropped row
    that is not a "24 Hour" notice, and one summary row when the dropped rows or dollars exceed max_share of the
    notice rows or dollars. -#}
{% macro notice_dedupe_violations(stg, kept, max_share=0.15) -%}
with dropped as (
    select
        s.record_id,
        s.report,
        s.amount
    from {{ stg }} as s
    where not exists (
        select 1
        from {{ kept }} as k
        where k.record_id = s.record_id
    )
),

notice_totals as (
    select
        count(*) as n_rows,
        sum(n.amount) as total
    from {{ stg }} as n
    where lower(n.report) like '%24 hour%'
),

dropped_totals as (
    select
        count(*) as n_rows,
        sum(d.amount) as total
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
    'dropped more than {{ (max_share * 100) | int }}% of the notice rows or dollars' as record_id,
    null as report,
    dd.total as amount
from dropped_totals as dd
cross join notice_totals as nd
where dd.n_rows > nd.n_rows * {{ max_share }} or dd.total > nd.total * {{ max_share }}
{%- endmacro %}
