-- Sanity check: the loader parses each vote's "Vacancies—N". If it is null on every row, the raw data predates the
-- vacancy parse (mo_senate was never reloaded), and assert_senate_seats_sum_to_34 would pass by skipping every vote.
-- Fails with one row in that case. Fix: `uv run mogov load mo_senate`, then rebuild.
{{ config(severity='error') }}

select
    count(*) as vote_rows,
    count(vacancies) as rows_with_vacancies
from {{ ref('stg_mo_senate__votes') }}
having count(*) > 0 and count(vacancies) = 0
