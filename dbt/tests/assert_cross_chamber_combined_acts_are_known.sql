-- Sanity check (#453): a combined act whose lead bill and combined bill are in different chambers ("S.B. 111 & H.B.
-- 130") is read as one substitute carrying both bills' subjects. That reading isn't proven (confirming it needs the
-- journals), so every such act is pinned here after a spot-check: 5 acts, all before 2017 (1977, 1981, 1982, 1998,
-- 2005). A new one, or a lead and combined bill that changed, fails the build so someone looks at it before it is
-- relied on. Update the list below when the spot-check of the new act is done. Returns the unexpected acts.
with cross_chamber as (
    select distinct
        act_year,
        extra_session,
        combined_into as lead_bill,
        bill as combined_bill
    from {{ ref('int_mo_revisor__session_law_bills') }}
    where
        combined_into is not null
        and substr(bill, 1, 1) != substr(combined_into, 1, 1)
),

known as (
    select
        1977 as act_year,
        'SB111' as lead_bill,
        'HB130' as combined_bill
    union all
    select
        1981 as act_year,
        'HB519' as lead_bill,
        'SB16' as combined_bill
    union all
    select
        1982 as act_year,
        'SB649' as lead_bill,
        'HB1096' as combined_bill
    union all
    select
        1998 as act_year,
        'SB820' as lead_bill,
        'HB1587' as combined_bill
    union all
    select
        2005 as act_year,
        'HB353' as lead_bill,
        'SB254' as combined_bill
)

select c.*
from cross_chamber as c
left join known as k
    on
        c.act_year = k.act_year
        and c.lead_bill = k.lead_bill
        and c.combined_bill = k.combined_bill
where k.act_year is null or c.extra_session is not null
