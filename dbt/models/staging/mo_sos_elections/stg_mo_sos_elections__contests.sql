-- Missouri Secretary of State official returns: one row per contest as titled in the PDF (a header line such as
-- "State Representative - District 34 (11 of 11 Precincts Reported)"), with the office, the district number when
-- the title has one, and the precinct counts. A retention block holding several judges is one contest here.
-- has_party_totals: the contest prints "Party Total" lines, i.e. it is a primary split into one ballot per party
-- (a special election held on primary day prints none and is one race across all parties).
with headers as (
    select
        election_key,
        election_type,
        election_date,
        pdf_url,
        page,
        contest_seq,
        trim({{ mogov.regex_replace_all('line_text', ' [(][0-9]+ of [0-9]+ Precincts Reported[)]$', '') }})
            as raw_title,
        {{ mogov.regex_extract('line_text', '[(]([0-9]+ of [0-9]+) Precincts Reported[)]$') }} as precinct_counts
    from {{ ref('stg_mo_sos_elections__lines') }}
    where kind = 'header'
),

party_totals as (
    select distinct
        election_key,
        contest_seq
    from {{ ref('stg_mo_sos_elections__lines') }}
    where kind = 'party_total'
),

titled as (
    select
        *,
        -- "U. S. Senator" (2016) and "U.S. Senator" are one office
        {{ mogov.regex_replace_all('raw_title', '^U[.] S[.]', 'U.S.') }} as contest_title
    from headers
)

select
    t.election_key,
    t.election_type,
    t.election_date,
    t.pdf_url,
    t.page,
    t.contest_seq,
    t.contest_title,
    trim({{ dbt.split_part('t.contest_title', "' - '", 1) }}) as office,
    {{ mogov.regex_extract('t.contest_title', 'District ([0-9]+)') }} as district,
    {{ dbt.safe_cast(dbt.split_part('t.precinct_counts', "' of '", 1), dbt.type_int()) }} as precincts_reported,
    {{ dbt.safe_cast(dbt.split_part('t.precinct_counts', "' of '", 2), dbt.type_int()) }} as precincts_total,
    p.contest_seq is not null as has_party_totals
from titled as t
left join party_totals as p on t.election_key = p.election_key and t.contest_seq = p.contest_seq
