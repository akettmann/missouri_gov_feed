-- Sanity check on the House roll-call token matching (#539): a named token that stays unattributed on more than a
-- handful of roll calls in a year is a systematic gap (a compound surname, a dropped suffix, a shared surname the
-- seat dates cannot split), not a stray typo. REHDER, REISCH, EVANS and ROWLAND each failed on hundreds of roll
-- calls before. The Speaker is attributed from a seed and is not named in the PDFs.
-- A warning, not an error (#581): a new session's roll calls can load before that session's roster does, and then
-- every freshman's token is unmatched for a while. That is a load-order gap that fixes itself on the next sync, not
-- a broken build, so it must not block the models that read this one; the warning still names the tokens.
-- The error-level guard is assert_vote_attribution_share_per_session (#660, #629 item 3): per session, it skips a
-- session with no roster rows yet (the load-order case) and fails when the attributed share drops under its floor.
{{ config(severity='warn') }}

select
    member_token,
    extract(year from vote_date) as vote_year,
    count(*) as unattributed_votes
from {{ ref('int_mo_house__votes') }}
where
    person_key is null
    and member_token != 'MR SPEAKER'
group by member_token, extract(year from vote_date)
having count(*) > 10
