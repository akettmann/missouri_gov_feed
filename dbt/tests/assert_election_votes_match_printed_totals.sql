-- Reconciliation with the PDF: a contest's candidate (or Yes and No) votes add up to the "Total Votes" line printed
-- under it. Skipped where the PDF prints no total for the contest, or one total for a block of several judges
-- (2022 Court of Appeals, Western District prints the first judge's total once), and in primaries, whose total
-- spans every party's ballot (the sum over the whole contest is compared there too).
with sums as (
    select
        election_key,
        contest_seq,
        subcontest_seq,
        sum(votes) as counted_votes
    from {{ ref('stg_mo_sos_elections__results') }}
    group by election_key, contest_seq, subcontest_seq
),

totals as (
    select
        election_key,
        contest_seq,
        subcontest_seq,
        printed_total_votes,
        count(*) over (partition by election_key, contest_seq) as totals_in_contest
    from {{ ref('stg_mo_sos_elections__printed_totals') }}
),

subs as (
    select
        election_key,
        contest_seq,
        count(*) as subs_in_contest
    from sums
    group by election_key, contest_seq
)

select
    s.election_key,
    s.contest_seq,
    s.subcontest_seq,
    s.counted_votes,
    t.printed_total_votes
from sums as s
inner join totals as t
    on s.election_key = t.election_key and s.contest_seq = t.contest_seq and s.subcontest_seq = t.subcontest_seq
inner join subs
    on s.election_key = subs.election_key and s.contest_seq = subs.contest_seq
where t.totals_in_contest = subs.subs_in_contest and s.counted_votes <> t.printed_total_votes
