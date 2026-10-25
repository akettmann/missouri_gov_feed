-- One row per judge on a retention ballot in Missouri's official returns (general and primary elections, 2012 on):
-- Yes and No votes and the printed Yes share. A judge is retained with a majority of Yes votes. Where the PDF
-- loses the No line (a few 2016 rows), no_votes is null. judge_official_id is set when the judge is a current
-- Supreme Court or Court of Appeals judge (same name and office); circuit judges are not linked.
with picks as (
    select
        *,
        case when choice_kind = 'yes' then votes end as yes_votes_,
        case when choice_kind = 'no' then votes end as no_votes_,
        case when choice_kind = 'yes' then pct_printed end as yes_pct_,
        case when choice_kind = 'no' then pct_printed end as no_pct_
    from {{ ref('stg_mo_sos_elections__results') }}
    where contest_kind = 'retention'
),

judges as (
    select
        election_key,
        election_type,
        election_date,
        contest_seq,
        subcontest_seq,
        contest_title,
        office,
        max(choice_name) as judge_name,
        max(yes_votes_) as yes_votes,
        max(no_votes_) as no_votes,
        max(yes_pct_) as yes_pct,
        max(no_pct_) as no_pct,
        max(precincts_reported) as precincts_reported,
        max(precincts_total) as precincts_total,
        max(pdf_url) as source_url
    from picks
    group by election_key, election_type, election_date, contest_seq, subcontest_seq, contest_title, office
    having max(yes_votes_) is not null
),

links as (
    select
        j.election_key,
        j.contest_seq,
        j.subcontest_seq,
        case when count(distinct c.official_id) = 1 then max(c.official_id) end as judge_official_id
    from judges as j
    inner join {{ ref('election_office_keys') }} as k on j.office = k.office
    inner join {{ ref('int_officials__current') }} as c on k.official_office = c.office
    inner join {{ ref('int_officials__name_keys') }} as nk
        on
            c.official_id = nk.official_id
            and {{ mogov.regex_replace_all(mogov.name_key('j.judge_name'), ' (jr|sr|ii|iii|iv)$', '') }}
            = nk.variant_key
    group by j.election_key, j.contest_seq, j.subcontest_seq
)

select
    j.election_key,
    j.election_type,
    j.election_date,
    j.contest_seq,
    j.subcontest_seq,
    j.contest_title,
    j.office,
    j.judge_name,
    cast(j.yes_votes as {{ dbt.type_bigint() }}) as yes_votes,
    cast(j.no_votes as {{ dbt.type_bigint() }}) as no_votes,
    cast(j.yes_pct as decimal(5, 1)) as yes_pct,
    cast(j.no_pct as decimal(5, 1)) as no_pct,
    j.yes_pct > 50 as is_retained,
    j.precincts_reported,
    j.precincts_total,
    l.judge_official_id,
    j.source_url
from judges as j
left join links as l
    on j.election_key = l.election_key and j.contest_seq = l.contest_seq and j.subcontest_seq = l.subcontest_seq
