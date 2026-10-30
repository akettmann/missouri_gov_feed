-- One row per statewide-office term in the Official Manual's historical listings
-- (int_bluebook__statewide_officeholders) with exact start and end dates, and the current official who served it
-- when there is one.
-- The Manual gives whole years only. Dates come from, in order:
--   1. the statewide_office_handovers seed when a row matches (office, term start year, family name): a hand-over on a
--      day other than the regular one (a resignation, death or appointment; Hawley left the Attorney General's office
--      on 2019-01-03);
--   2. the observed swearing-in practice: a term begins on the second Monday of January of its first year and ends on
--      the second Monday of January of its last year when that is an inauguration year (2017, 2021, 2025; the
--      auditor's 2015, 2019, 2023). RSMo 27.010 sets this for the Attorney General only; the other five offices are
--      the same by practice (2017-01-09, 2019-01-14, 2021-01-11, 2023-01-09, 2025-01-13);
--   3. otherwise the term ended mid-term in its last year and no date is known: December 31 of that year. The test
--      assert_statewide_handovers_cover_mid_term_changes lists those that still need a seed row.
-- An open term (term_end_year null) ends 9999-12-31.
-- official_id is the person's dim_official id when they also hold a tracked office today (matched on first and last
-- name, or on a known variant such as "Josh Hawley" for Open States' "Joshua"; null for people who left public
-- life). A name that fits two current officials matches neither. A former governor who is now a senator links to the
-- senator's profile.
-- A name alone is not enough: Governor Benjamin Gratz Brown (1871) and the current legislator Ben Brown share one
-- (#760). The match is kept only when the person's known service corroborates it (official_id_basis):
--   same_office     the term is for the office the official holds today (Malek, Treasurer 2023 and 2025);
--   service_overlap the term overlaps, or lies within a year of, a dated stretch of service we know for the official
--                   (Open States roles, congress-legislators terms, Wikidata positions, the current term): Hawley's
--                   2017-2019 Attorney General term ends the day his Senate term starts.
-- Otherwise official_id is null, so every consumer gets the guard instead of only fct_office_history.
{% set end_year_text = dbt.safe_cast('b.term_end_year', dbt.type_string()) %}
{% set family_of_holder = mogov.name_key(mogov.regex_extract('b.full_name', '([^ ]+)$')) %}
with holders as (
    select
        b.office,
        b.full_name,
        b.party,
        b.term_start_year,
        b.term_end_year,
        coalesce(o.term_start, {{ mogov.second_monday_of_january('b.term_start_year') }}) as term_start,
        coalesce(
            o.term_end,
            case
                when b.term_end_year is null then {{ dbt.safe_cast("'9999-12-31'", 'date') }}
                -- a term that ends in an inauguration year ends at the January hand-over (the auditor's inaugurations
                -- are in years 3 mod 4, the others' 1 mod 4); any other end year is a mid-term change not in the seed
                when mod(b.term_end_year, 4) = case b.office when 'state_auditor' then 3 else 1 end
                    then {{ mogov.second_monday_of_january('b.term_end_year') }}
                else
                    {{ dbt.safe_cast(dbt.concat([end_year_text, "'-12-31'"]), 'date') }}
            end
        ) as term_end,
        {{ mogov.name_key(dbt.split_part('b.full_name', "' '", 1)) }} as given_key,
        {{ family_of_holder }} as family_key
    from {{ ref('int_bluebook__statewide_officeholders') }} as b
    left join {{ ref('statewide_office_handovers') }} as o
        on
            b.office = o.office
            and b.term_start_year = o.term_start_year
            and {{ mogov.name_key(mogov.regex_extract('b.full_name', '([^ ]+)$')) }}
            = {{ mogov.name_key('o.family_name') }}
),

-- current officials by name; a key that fits two officials is dropped rather than guessed. Both "first last" as the
-- Manual prints it ("Josh Hawley", whom Open States calls Joshua) and the official's other known variants match.
name_matches as (
    select
        variant_key as match_key,
        official_id
    from {{ ref('int_officials__name_keys') }}
    union
    select
        given_key || ' ' || family_key as match_key,
        official_id
    from {{ ref('int_officials__name_keys') }}
),

current_by_name as (
    select
        match_key,
        min(official_id) as official_id
    from name_matches
    group by match_key
    having count(distinct official_id) = 1
),

-- dated stretches of service we know for each current official; a null end is still serving
known_service as (
    select
        official_id,
        office,
        current_term_start as start_date,
        coalesce(current_term_end, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date
    from {{ ref('int_officials__current') }}
    where current_term_start is not null
    union all
    select
        o.official_id,
        cast(null as {{ dbt.type_string() }}) as office,
        r.start_date,
        coalesce(r.end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date
    from {{ ref('int_officials__current') }} as o
    inner join (
        select
            coalesce(x.person_id, ro.openstates_id) as person_id,
            ro.start_date,
            ro.end_date
        from {{ ref('stg_openstates__roles') }} as ro
        left join {{ ref('int_officials__person_ids') }} as x on ro.openstates_id = x.alias_id
    ) as r on o.official_id = r.person_id
    where r.start_date is not null
    union all
    select
        o.official_id,
        cast(null as {{ dbt.type_string() }}) as office,
        t.start_date,
        coalesce(t.end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('stg_congress__terms') }} as t on o.bioguide_id = t.bioguide_id
    where t.start_date is not null
    union all
    select
        q.official_id,
        cast(null as {{ dbt.type_string() }}) as office,
        f.start_date,
        coalesce(f.end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date
    from {{ ref('int_officials__wikidata') }} as q
    inner join {{ ref('stg_wikidata__facts') }} as f on q.qid = f.qid
    where f.fact_kind = 'position held' and f.start_date is not null
),

candidates as (
    select
        h.*,
        c.official_id as candidate_id
    from holders as h
    left join current_by_name as c on h.given_key || ' ' || h.family_key = c.match_key
),

-- the strongest corroboration per candidate (a term can have several)
basis as (
    select
        c.office,
        c.full_name,
        c.term_start_year,
        c.candidate_id,
        min(
            case
                when k.office = c.office then 'same_office'
                else 'service_overlap'
            end
        ) as official_id_basis
    from candidates as c
    inner join known_service as k
        on
            c.candidate_id = k.official_id
            and (
                k.office = c.office
                -- within a year either side: the Manual lists whole years, the sources exact days
                or (
                    {{ dbt.dateadd('day', -366, 'c.term_start') }} <= k.end_date
                    and {{ dbt.dateadd('day', -366, 'k.start_date') }} <= c.term_end
                )
            )
    group by c.office, c.full_name, c.term_start_year, c.candidate_id
)

select
    c.office,
    c.full_name,
    c.party,
    c.term_start_year,
    c.term_end_year,
    c.term_start,
    c.term_end,
    c.given_key,
    c.family_key,
    b.candidate_id as official_id,
    b.official_id_basis
from candidates as c
left join basis as b
    on
        c.office = b.office
        and c.full_name = b.full_name
        and c.term_start_year = b.term_start_year
        and c.candidate_id = b.candidate_id
