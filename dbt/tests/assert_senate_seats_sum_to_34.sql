-- Sanity check: every Senate journal vote accounts for all 34 seats. Senators listed (yea, nay, absent, absent with
-- leave, recused) plus the journal's printed "Vacancies—N" must equal 34. A different total means a parse bug
-- (a name dropped, split or merged) or a block cut short. Votes without a parsed vacancy count are skipped here;
-- assert_senate_vacancies_parsed fails if that is every vote, and the 34-seat cap in assert_votes_within_seats
-- still covers them.
--
-- Allow-list: votes where the journal itself prints a short roll. Each entry needs a reason.
--   * 21info/Journals/RDay5804291051-1071.pdf #4 (2021-04-29, SS for HCS for HB 574): the journal prints YEAS 23
--     and NAYS 9 (32 names, matching its own totals) and no other section, so Eigel and Hough appear nowhere in the
--     roll call. The parsed rows equal the printed lists; the parser drops nothing here.
{{ config(severity='error') }}

with known_short_votes as (
    select 'https://www.senate.mo.gov/21info/Journals/RDay5804291051-1071.pdf#vote4' as vote_id
)

select
    votes.vote_id,
    max(votes.vacancies) as vacancies,
    count(*) as senators_listed,
    count(*) + max(votes.vacancies) as seats_accounted_for
from {{ ref('stg_mo_senate__votes') }} as votes
where
    votes.vacancies is not null
    and votes.vote_id not in (select known_short_votes.vote_id from known_short_votes)
group by votes.vote_id
having count(*) + max(votes.vacancies) != 34
