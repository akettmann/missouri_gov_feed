-- Sanity check: a relisted bill (the House's repeat of the previous regular session's appropriation bill, listed only
-- to record the governor's Art. IV, s. 27 message) names the session it repeats whenever that session is loaded. All
-- 128 relistings with the prior regular session loaded match it on bill number and bill string; the 15 of 2017 repeat
-- 2016's session (161), which isn't loaded. A miss means the relisting is a real new bill or the bill string drifted.
select
    r.session_code,
    r.bill
from {{ ref('fct_bills') }} as r
where
    r.status = 'relisted for governor message'
    and r.relisted_from_session_code is null
    and exists (
        select 1
        from {{ ref('fct_bills') }} as p
        where p.session_code = {{ dbt.concat([dbt.safe_cast('r.session_year - 2001', dbt.type_string()), "'1'"]) }}
    )
