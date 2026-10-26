-- Sanity check: every Senate journal vote accounts for all 34 seats. Senators listed (yea, nay, absent, absent with
-- leave, recused) plus the journal's printed "Vacancies—N" must equal 34. A different total means a parse bug
-- (a name dropped, split or merged) or a block cut short. Votes without a parsed vacancy count are skipped: the
-- 34-seat cap in assert_votes_within_seats still covers them.
{{ config(severity='warn') }}

select
    vote_id,
    max(vacancies) as vacancies,
    count(*) as senators_listed,
    count(*) + max(vacancies) as seats_accounted_for
from {{ ref('stg_mo_senate__votes') }}
where vacancies is not null
group by vote_id
having count(*) + max(vacancies) != 34
