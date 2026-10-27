-- A Senate bill list or action row whose (year, session type) has no row in the mo_senate_session_codes seed has no
-- House session code, so int_bills__list drops the bill (a new special session lands here first, the loader reads a
-- 10-year window by default). To fix: find the House session code of the same special session (stg_mo_house__bills /
-- stg_mo_house__senate_act_bills: the code whose bills share the Senate's titles and whose action dates overlap the
-- Senate's), then add one line to dbt/seeds/mo_senate_session_codes.csv:
--   <year>,E<n>,<house code>,"<month year> special session: Senate E<n> SB<k> '<title>' matches House <code> HB<j>
--   '<title>'; Senate <dates>, House <dates>"
-- Evidence is required, never arithmetic (the House has no 252; 2025 E1 is 253). Run `dbt seed` and rebuild.
-- Known gap: the Senate site returns an empty list for 2017 E1 (the House has 173 and 174), so those Senate bills are
-- not landed and need no row.
select
    'bills' as kind,
    session_year,
    session_type,
    count(*) as unmapped_rows,
    'add a row to dbt/seeds/mo_senate_session_codes.csv, with title and date evidence (see this test''s header)'
        as how_to_fix
from {{ ref('stg_mo_senate__bills') }}
where session_code is null
group by session_year, session_type

union all

select
    'actions' as kind,
    session_year,
    session_type,
    count(*) as unmapped_rows,
    'add a row to dbt/seeds/mo_senate_session_codes.csv, with title and date evidence (see this test''s header)'
        as how_to_fix
from {{ ref('stg_mo_senate__bill_actions') }}
where session_code is null
group by session_year, session_type
