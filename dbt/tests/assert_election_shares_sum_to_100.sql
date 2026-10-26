-- The percentages the SoS prints for a race (a party's ballot in a primary, one judge's Yes and No rows) are rounded
-- to a tenth, so they sum to 100 within 0.1 per choice. A larger gap means a candidate row was dropped or misread.
-- A lone row in a primary party ballot must print 100% (an unopposed candidate; a lone row there with less means
-- the contest is not really split by party, as with the special elections held on primary day). A lone row
-- elsewhere is skipped (the 2016 PDF loses a No line); a ballot measure's Yes/No rows count too.
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
        case when election_type = 'primary' and has_party_totals then coalesce(party, '') else '' end as party_ballot
    from {{ ref('stg_mo_sos_elections__results') }}
    where not (election_type = 'primary' and party = 'Write-in')
) as p
group by election_key, contest_seq, subcontest_seq, party_ballot
having
    abs(sum(pct_printed) - 100) > 0.1 * count(*)
    and (count(*) > 1 or party_ballot != '')
