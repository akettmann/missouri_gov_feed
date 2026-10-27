-- A Senate bill list or action row whose (year, session type) has no row in the mo_senate_session_codes seed has no
-- House session code, so int_bills__list drops the bill. Add the session to the seed with evidence (the same bills
-- under the House's code), never by arithmetic: the House has no 252 and 2025 E1 is 253.
select
    'bills' as kind,
    session_year,
    session_type,
    count(*) as unmapped_rows
from {{ ref('stg_mo_senate__bills') }}
where session_code is null
group by session_year, session_type

union all

select
    'actions' as kind,
    session_year,
    session_type,
    count(*) as unmapped_rows
from {{ ref('stg_mo_senate__bill_actions') }}
where session_code is null
group by session_year, session_type
