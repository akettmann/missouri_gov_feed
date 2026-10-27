-- Sanity check (#317): in every finished session whose Senate action history is loaded, at least 95% of the
-- HB/SB/HJR/SJR rows of fct_bills have a status. A mass gap means the Senate actions did not land, or the wording
-- mapping (seed mo_senate_action_flags) stopped matching. The few Senate bills whose Actions tab was rejected at
-- load time (under 5% of a shard, #637) have no status by design (unknown, not a stage). Sessions before this
-- year only, and only those the Senate action history covers.
with covered as (
    select distinct session_code
    from {{ ref('stg_mo_senate__bill_actions') }}
    where session_code is not null
)

select
    b.session_code,
    count(*) as bills,
    sum(case when b.status is null then 1 else 0 end) as without_status
from {{ ref('fct_bills') }} as b
inner join covered as c on b.session_code = c.session_code
where
    b.session_year < extract(year from current_date)
    and {{ mogov.regex_extract('b.bill', '^([A-Z]+)') }} in ('HB', 'SB', 'HJR', 'SJR')
group by b.session_code
having sum(case when b.status is null then 1 else 0 end) > 0.05 * count(*)
