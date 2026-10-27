-- Every action row belongs to a bill of the Senate list (same year, session and billId), and its date falls within a
-- year of the session year (a regular session's bills are acted on from the December before to the year after; an
-- action 10 years out is a mis-parsed date). Null dates are the staging model's own warning.
select
    a.session_year,
    a.session_type,
    a.bill_id,
    a.action_index,
    a.action_date
from {{ ref('stg_mo_senate__bill_actions') }} as a
left join {{ ref('stg_mo_senate__bills') }} as b
    on a.session_year = b.session_year and a.session_type = b.session_type and a.bill_id = b.bill_id
where
    b.bill_id is null
    or a.action_date < {{ dbt.dateadd('year', -1, "cast(a.session_year || '-01-01' as date)") }}
    or a.action_date > {{ dbt.dateadd('year', 2, "cast(a.session_year || '-01-01' as date)") }}
