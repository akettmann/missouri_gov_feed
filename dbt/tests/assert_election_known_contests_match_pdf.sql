-- Spot checks against the 2024 general election PDF (https://www.sos.mo.gov/CMSImages/ElectionResultsStatistics/
-- 2024GeneralElection.pdf), figures copied from the printed pages: a mismatch or a missing row fails. The test
-- passes when the 2024 general election is not loaded at all.
with expected_races as (
    select
        'Governor' as contest_title,
        'Mike Kehoe' as winner_name,
        1750802 as winner_votes,
        'Crystal Quade' as runner_up_name,
        2960266 as total_votes,
        604629 as margin_votes,
        false as is_uncontested
    union all
    select
        'U.S. Senator' as contest_title,
        'Josh Hawley' as winner_name,
        1651907 as winner_votes,
        'Lucas Kunce' as runner_up_name,
        2972559 as total_votes,
        408179 as margin_votes,
        false as is_uncontested
    union all
    select
        'State Representative - District 34' as contest_title,
        'Kemp Strickler' as winner_name,
        10172 as winner_votes,
        'JC Crossley' as runner_up_name,
        19635 as total_votes,
        709 as margin_votes,
        false as is_uncontested
    union all
    select
        'State Representative - District 33' as contest_title,
        'Carolyn S. Caton' as winner_name,
        16427 as winner_votes,
        null as runner_up_name,
        16427 as total_votes,
        null as margin_votes,
        true as is_uncontested
),

expected_judges as (
    select
        'Missouri Supreme Court' as contest_title,
        'Kelly C. Broniec' as judge_name,
        1634157 as yes_votes,
        63.1 as yes_pct
    union all
    select
        'Missouri Supreme Court' as contest_title,
        'Ginger K. Gooch' as judge_name,
        1606477 as yes_votes,
        62.2 as yes_pct
),

loaded as (
    select count(*) as n from {{ ref('fct_election_races') }}
    where election_key = '2024-11-05-general'
)

select
    'race' as kind,
    e.contest_title as what
from expected_races as e
cross join loaded
left join {{ ref('fct_election_races') }} as r
    on r.election_key = '2024-11-05-general' and e.contest_title = r.contest_title
where
    loaded.n > 0
    and (
        r.winner_name is null
        or r.winner_name <> e.winner_name
        or r.winner_votes <> e.winner_votes
        or r.total_votes <> e.total_votes
        or r.is_uncontested <> e.is_uncontested
        or coalesce(r.runner_up_name, '') <> coalesce(e.runner_up_name, '')
        or coalesce(r.margin_votes, -1) <> coalesce(e.margin_votes, -1)
    )

union all

select
    'judge' as kind,
    e.judge_name as what
from expected_judges as e
cross join loaded
left join {{ ref('fct_judicial_retention') }} as j
    on j.election_key = '2024-11-05-general' and e.contest_title = j.contest_title and e.judge_name = j.judge_name
where loaded.n > 0 and (j.yes_votes is null or j.yes_votes <> e.yes_votes or j.yes_pct <> e.yes_pct)
