-- Every ballot measure (a contest titled Constitutional Amendment, Proposition or Constitutional Convention Question,
-- 2012-2024 in every layout the PDFs use) has exactly one Yes row and one No row, with some votes cast. The 2014-2020
-- "Ballot Issue Yes: n Yes: p%" layout once lost all its rows (#331). Returns the measures that break this.
-- There are no known exceptions (the 2016 No row that lost its percent sign belongs to a retention judge).
with measures as (
    select
        election_key,
        contest_seq,
        contest_title
    from {{ ref('stg_mo_sos_elections__contests') }}
    where
        {{ mogov.regex_matches('contest_title', '^(Constitutional Amendment|Proposition|Constitutional Convention)') }}
),

counted as (
    select
        election_key,
        contest_seq,
        sum(case when choice_kind = 'yes' then 1 else 0 end) as yes_rows,
        sum(case when choice_kind = 'no' then 1 else 0 end) as no_rows,
        sum(votes) as yes_plus_no_votes
    from {{ ref('stg_mo_sos_elections__results') }}
    where contest_kind = 'ballot_issue'
    group by election_key, contest_seq
)

select
    m.election_key,
    m.contest_seq,
    m.contest_title,
    c.yes_rows,
    c.no_rows,
    c.yes_plus_no_votes
from measures as m
left join counted as c on m.election_key = c.election_key and m.contest_seq = c.contest_seq
where c.contest_seq is null or c.yes_rows <> 1 or c.no_rows <> 1 or c.yes_plus_no_votes <= 0
