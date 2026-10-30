-- Sanity check on Senate vote attribution (#534). Every journal roll-call token is matched to the senator serving
-- on the vote date (int_mo_senate__votes); an ambiguous or unmatched token stays unattributed. All 75,677 votes
-- (2017-2026) are attributed today. int_mo_legislators__seats dates Senate terms from those attributions, so a
-- name format that stops matching would shorten terms. Fails, with one row per unattributed token, when more than
-- 0.05% of the vote rows (about 38 today) are unattributed.
{{ config(severity='error') }}

with totals as (
    select
        count(*) as vote_rows,
        count(*) - count(person_key) as unattributed_rows
    from {{ ref('int_mo_senate__votes') }}
)

select
    v.member_token,
    count(*) as unattributed_votes,
    min(v.vote_date) as first_date,
    max(v.vote_date) as last_date,
    max(t.vote_rows) as vote_rows
from {{ ref('int_mo_senate__votes') }} as v
cross join totals as t
where v.person_key is null and t.unattributed_rows * 2000 > t.vote_rows
group by v.member_token
