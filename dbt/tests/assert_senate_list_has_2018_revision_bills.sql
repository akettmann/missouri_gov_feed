-- The Senate topical index omits bills filed under no keyword, e.g. 2018 SB 975 and 1024 (a revision bill that
-- repealed 91 sections and amended 4, per the Revisor; #237). The Senate numbers them SRB975 and SRB1024 (revision
-- bills). Once the Senate's own list for the 2018 regular session is loaded, both must be in the bill list. Passes
-- when 2018 is not loaded.
with listed as (
    select count(*) as n
    from {{ ref('stg_mo_senate__bills') }}
    where session_code = '181'
),

wanted as (
    select 'SRB975' as bill

    union all

    select 'SRB1024' as bill
)

select w.bill
from wanted as w
cross join listed as l
left join {{ ref('int_bills__list') }} as b on w.bill = b.bill and b.session_code = '181'
where l.n > 0 and b.bill is null
