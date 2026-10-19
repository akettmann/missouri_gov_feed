-- Which House bill each state vote was on, so votes can be grouped by bill subject (fct_bill_subjects).
--   House roll calls: the bill XML names the roll-call PDF, which is the vote_id (exact).
--   Senate journal votes: the vote's measure ("HB 2") read from the journal text, matched to the House bill
--   of that year's regular session; Senate bills are not covered yet.
select distinct
    'state_house' as chamber,
    r.rollcall_url as vote_id,
    r.session_code,
    r.bill,
    r.bill_version,
    'roll-call link' as matched_by
from {{ ref('stg_mo_house__bill_rollcalls') }} as r
where r.rollcall_url is not null

union all

select distinct
    'state_senate' as chamber,
    v.vote_id,
    b.session_code,
    b.bill,
    cast(null as {{ dbt.type_string() }}) as bill_version,
    'measure text' as matched_by
from {{ ref('int_mo_senate__votes') }} as v
inner join {{ ref('stg_mo_house__bills') }} as b
    on
        replace(v.measure, ' ', '') = b.bill
        and {{ dbt.right(dbt.safe_cast('extract(year from v.vote_date)', dbt.type_string()), 2) }} || '1'
        = b.session_code
where v.measure like 'H%'
