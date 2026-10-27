-- Sanity check on the House roll-call token matching (#539): a named token that stays unattributed on more than a
-- handful of roll calls in a year is a systematic gap (a compound surname, a dropped suffix, a shared surname the
-- seat dates cannot split), not a stray typo. REHDER, REISCH, EVANS and ROWLAND each failed on hundreds of roll
-- calls before. The Speaker is attributed from a seed and is not named in the PDFs.
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
