-- One row per race in Missouri's official returns (general and primary elections, 2012 on): the winner, the
-- runner-up, the margin and whether the winner had no opponent. A primary race is one party's ballot, except a
-- special election held on primary day (no "Party Total" lines), which is one race across all parties.
-- winner_official_id is set when the winner is a current official (same name, same office, same district).
with candidates as (
    select
        *,
        case when election_type = 'primary' and has_party_totals then party end as race_party
    from {{ ref('stg_mo_sos_elections__results') }}
    where contest_kind = 'candidate'
),

placed as (
    select
        *,
        sum(votes) over (partition by election_key, contest_seq, race_party) as race_votes,
        sum(case when is_write_in then votes else 0 end) over (
            partition by election_key, contest_seq, race_party
        ) as write_in_votes,
        sum(case when is_write_in then 0 else 1 end) over (
            partition by election_key, contest_seq, race_party
        ) as n_candidates,
        row_number() over (
            partition by election_key, contest_seq, race_party, is_write_in
            order by votes desc, choice_name asc
        ) as place
    from candidates
),

races as (
    select
        election_key,
        election_type,
        election_date,
        contest_seq,
        race_party,
        contest_title,
        office,
        district,
        max(race_votes) as race_votes,
        max(write_in_votes) as write_in_votes,
        max(n_candidates) as n_candidates,
        max(case when not is_write_in and place = 1 then choice_name end) as winner_name,
        max(case when not is_write_in and place = 1 then party end) as winner_party,
        max(case when not is_write_in and place = 1 then votes end) as winner_votes,
        max(case when not is_write_in and place = 2 then choice_name end) as runner_up_name,
        max(case when not is_write_in and place = 2 then party end) as runner_up_party,
        max(case when not is_write_in and place = 2 then votes end) as runner_up_votes,
        max(precincts_reported) as precincts_reported,
        max(precincts_total) as precincts_total,
        max(pdf_url) as source_url
    from placed
    group by election_key, election_type, election_date, contest_seq, race_party, contest_title, office, district
    having max(n_candidates) > 0
),

links as (
    select
        r.election_key,
        r.contest_seq,
        r.race_party,
        case when count(distinct c.official_id) = 1 then max(c.official_id) end as winner_official_id
    from races as r
    inner join {{ ref('election_office_keys') }} as k on r.office = k.office
    inner join {{ ref('int_officials__current') }} as c
        on k.official_office = c.office and coalesce(r.district, '') = coalesce(c.district, '')
    inner join {{ ref('int_officials__name_keys') }} as nk
        on
            c.official_id = nk.official_id
            and {{ mogov.regex_replace_all(mogov.name_key('r.winner_name'), ' (jr|sr|ii|iii|iv)$', '') }}
            = nk.variant_key
    group by r.election_key, r.contest_seq, r.race_party
)

select
    r.election_key,
    r.election_type,
    r.election_date,
    r.contest_seq,
    r.race_party,
    r.contest_title,
    r.office,
    r.district,
    cast(r.n_candidates as {{ dbt.type_int() }}) as candidates,
    r.n_candidates = 1 as is_uncontested,
    cast(r.race_votes as {{ dbt.type_bigint() }}) as total_votes,
    cast(r.write_in_votes as {{ dbt.type_bigint() }}) as write_in_votes,
    cast(round(r.write_in_votes * 100.0 / nullif(r.race_votes, 0), 2) as decimal(5, 2)) as write_in_share,
    r.winner_name,
    r.winner_party,
    cast(r.winner_votes as {{ dbt.type_bigint() }}) as winner_votes,
    cast(round(r.winner_votes * 100.0 / nullif(r.race_votes, 0), 2) as decimal(5, 2)) as winner_share,
    r.runner_up_name,
    r.runner_up_party,
    cast(r.runner_up_votes as {{ dbt.type_bigint() }}) as runner_up_votes,
    cast(r.winner_votes - r.runner_up_votes as {{ dbt.type_bigint() }}) as margin_votes,
    cast(round((r.winner_votes - r.runner_up_votes) * 100.0 / nullif(r.race_votes, 0), 2) as decimal(5, 2))
        as margin_pct,
    r.precincts_reported,
    r.precincts_total,
    l.winner_official_id,
    r.source_url
from races as r
left join links as l
    on
        r.election_key = l.election_key
        and r.contest_seq = l.contest_seq
        and r.race_party is not distinct from l.race_party
