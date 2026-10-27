-- Sanity check (#660, #629 item 3, #539, #534): in every House and Senate session, nearly every named roll-call vote
-- is attributed to a person (person_key filled). Fails for a House session where under 99.5% of the named votes
-- (MR SPEAKER excluded: the Speaker is attributed from a seed) are attributed, or a Senate session where more than
-- 0.05% are not, when more than 10 of the session's votes are unattributed. Guards a name format or seat-date
-- change that stops tokens matching: before #564 about 6.4k House votes (REHDER, REISCH, EVANS, ROWLAND) were
-- unattributed, and int_mo_legislators__seats dates Senate terms from these attributions, so a Senate gap also
-- shortens terms.
-- Floors, measured on a full build (2026-10): every House session (20 sessions, 480 to 136,765 named votes) and
-- every Senate session (2017-2026, 3,259 to 12,276 votes) is 100% attributed. 99.5% (House) and 0.05% unattributed
-- (Senate, the floor assert_senate_vote_tokens_attributed applies to the whole table) are far under that, yet one
-- member left unattributed for a session is hundreds of votes (REHDER alone was about 2.7k). The 10-vote minimum
-- keeps a stray misprinted token in a small special session (session 204 has 480 named votes, so 0.5% is 2 votes)
-- from failing the build; assert_house_vote_tokens_attributed still warns per token.
-- Load order: a House session whose roll calls are loaded before its roster (no rows yet in
-- int_mo_house__member_identity) leaves every token unmatched until the next sync; it is skipped, not failed.
{{ config(severity='error') }}

with house_rosters as (
    select distinct session_code
    from {{ ref('int_mo_house__member_identity') }}
),

votes as (
    select
        v.chamber,
        v.session_code,
        v.person_key
    from {{ ref('int_mo_house__votes') }} as v
    inner join house_rosters as r on v.session_code = r.session_code
    where v.member_token != 'MR SPEAKER'
    union all
    select
        chamber,
        session_code,
        person_key
    from {{ ref('int_mo_senate__votes') }}
),

shares as (
    select
        chamber,
        session_code,
        count(*) as named_votes,
        count(*) - count(person_key) as unattributed_votes
    from votes
    group by chamber, session_code
)

select
    chamber,
    session_code,
    named_votes,
    unattributed_votes
from shares
where
    unattributed_votes > 10
    and (
        (chamber = 'state_house' and unattributed_votes * 200 > named_votes)
        or (chamber = 'state_senate' and unattributed_votes * 2000 > named_votes)
    )
