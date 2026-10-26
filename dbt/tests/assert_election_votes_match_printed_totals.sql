-- Reconciliation with the PDF: a contest's candidate (or Yes and No) votes add up to the "Total Votes" line printed
-- under it. Skipped where the PDF prints no total for the contest, or one total for a block of several judges
-- (2022 Court of Appeals, Western District prints the first judge's total once), and in primaries, whose total
-- spans every party's ballot (the sum over the whole contest is compared there too).
-- Known PDF mismatches. 2014-08-05 primary Constitutional Amendment 1 (499,581 + 497,091 = 996,672, total printed
-- 997,551): the printed Yes/No lines are the pre-recount, uncertified figures; the printed total is the certified
-- post-recount one (the September 2014 recount gave Yes 499,963 + No 497,588 = 997,551). Amendment 9 (729,750 +
-- 246,515 = 976,265, printed 976,267) is a genuine 2-vote inconsistency within the PDF.
with known_pdf_mismatches as (
    select
        '2014-08-05-primary' as election_key,
        202 as contest_seq
    union all
    select
        '2014-08-05-primary' as election_key,
        206 as contest_seq
),

sums as (
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
left join known_pdf_mismatches as k
    on s.election_key = k.election_key and s.contest_seq = k.contest_seq
where
    t.totals_in_contest = subs.subs_in_contest
    and s.counted_votes <> t.printed_total_votes
    and k.contest_seq is null
