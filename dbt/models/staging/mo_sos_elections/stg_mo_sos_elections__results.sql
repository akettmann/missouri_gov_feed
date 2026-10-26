-- Missouri Secretary of State official returns: one row per contest x candidate or ballot choice x election, with
-- votes, party, the printed percentage and a write-in flag. A retention judge has a "Yes Votes" and a "No Votes"
-- row; a block of several judges under one header is split with subcontest_seq (it counts the Yes rows so far).
-- contest_kind: candidate, retention (judge Yes/No), ballot_issue (Yes/No on a measure whose name is the contest
-- title), in every layout (the 2014-2020 "Ballot Issue Yes: n" lines are recognised in the lines model).
with picks as (
    select
        l.line_key,
        l.election_key,
        l.election_type,
        l.election_date,
        l.pdf_url,
        l.page,
        l.line,
        l.contest_seq,
        l.cell_name,
        l.cell_party,
        l.cell_votes,
        l.cell_pct,
        case
            when l.cell_party = 'Yes Votes' then 'yes'
            when l.cell_party = 'No Votes' then 'no'
            else 'candidate'
        end as choice_kind,
        cast(sum(case when l.cell_party = 'Yes Votes' then 1 else 0 end) over (
            partition by l.election_key, l.contest_seq
            order by l.page, l.line
            rows between unbounded preceding and current row
        ) as {{ dbt.type_int() }}) as subcontest_seq
    from {{ ref('stg_mo_sos_elections__lines') }} as l
    where l.kind = 'candidate'
),

named as (
    select
        *,
        max(case when choice_kind = 'yes' then cell_name end) over (
            partition by election_key, contest_seq, subcontest_seq
        ) as yes_name
    from picks
)

select
    n.line_key,
    n.election_key,
    n.election_type,
    n.election_date,
    n.contest_seq,
    n.subcontest_seq,
    c.contest_title,
    c.office,
    c.district,
    c.has_party_totals,
    case
        when n.choice_kind = 'candidate' then 'candidate'
        when coalesce(n.cell_name, n.yes_name) = c.contest_title then 'ballot_issue'
        else 'retention'
    end as contest_kind,
    n.choice_kind,
    coalesce(n.cell_name, n.yes_name) as choice_name,
    case when n.choice_kind = 'candidate' then n.cell_party end as party,
    coalesce(lower(n.cell_party) = 'write-in', false) as is_write_in,
    n.cell_votes as votes,
    n.cell_pct as pct_printed,
    c.precincts_reported,
    c.precincts_total,
    n.pdf_url,
    n.page,
    n.line
from named as n
inner join {{ ref('stg_mo_sos_elections__contests') }} as c
    on n.election_key = c.election_key and n.contest_seq = c.contest_seq
