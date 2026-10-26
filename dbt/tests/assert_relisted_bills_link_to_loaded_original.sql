-- Sanity check: a relisted bill (the House's repeat of the previous regular session's appropriation bill, listed only
-- to record the governor's Art. IV, s. 27 message) names the session it repeats whenever that session is loaded. All
-- 128 relistings with the prior regular session loaded match it on bill number and bill string; the 15 of 2017 repeat
-- 2016's session (161), which isn't loaded. Fails on a relisting that
--   * has no link although the prior regular session is loaded (a real new bill, or the bill string drifted),
--   * links to its own session, or
--   * links to a session/bill that has no row in int_bills__status or fct_bills.
select
    r.session_code,
    r.bill,
    'missing link' as problem
from {{ ref('fct_bills') }} as r
where
    r.status = 'relisted for governor message'
    and r.relisted_from_session_code is null
    and exists (
        select 1
        from {{ ref('fct_bills') }} as p
        where p.session_code = {{ dbt.concat([dbt.safe_cast('r.session_year - 2001', dbt.type_string()), "'1'"]) }}
    )

union all

select
    r.session_code,
    r.bill,
    'links to own session' as problem
from {{ ref('fct_bills') }} as r
where r.relisted_from_session_code = r.session_code

union all

select
    r.session_code,
    r.bill,
    'original not in int_bills__status' as problem
from {{ ref('int_bills__status') }} as r
where
    r.relisted_from_session_code is not null
    and not exists (
        select 1
        from {{ ref('int_bills__status') }} as o
        where o.session_code = r.relisted_from_session_code and o.bill = r.bill
    )

union all

select
    r.session_code,
    r.bill,
    'original not in fct_bills' as problem
from {{ ref('fct_bills') }} as r
where
    r.relisted_from_session_code is not null
    and not exists (
        select 1
        from {{ ref('fct_bills') }} as o
        where o.session_code = r.relisted_from_session_code and o.bill = r.bill
    )
