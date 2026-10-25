-- The percentages the SoS prints for a race (a party's ballot in a primary, one judge's Yes and No rows) are rounded
-- to a tenth, so they sum to 100 within 0.1 per choice. A larger gap means a candidate row was dropped or misread.
-- A lone row is skipped (the 2016 PDF loses a No line); a ballot measure's Yes/No rows count too.
select
    election_key,
    contest_seq,
    subcontest_seq,
    party_ballot,
    count(*) as choices,
    sum(pct_printed) as pct_sum
from (
    select
        election_key,
        contest_seq,
        subcontest_seq,
        pct_printed,
        case when election_type = 'primary' then coalesce(party, '') else '' end as party_ballot
    from {{ ref('stg_mo_sos_elections__results') }}
    where not (election_type = 'primary' and party = 'Write-in')
) as p
group by election_key, contest_seq, subcontest_seq, party_ballot
having count(*) > 1 and abs(sum(pct_printed) - 100) > 0.1 * count(*)
