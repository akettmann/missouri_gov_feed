-- "Bias" indicators: ideology and party-loyalty measures (one part of the evidence on whom an
-- official works for), not judgments. Each row is one indicator for one official:
--   dw_nominate_dim1   Voteview, Congress. -1 liberal .. +1 conservative (economic dimension).
--   shor_mccarty_np    State legislators, 1993-2022. Negative liberal, positive conservative.
--   party_unity_pct    Share of party-line votes (majority of R vs majority of D) where the official
--                      voted with their own party's majority. Computed from the vote records here; the
--                      majorities count every member who voted, not just today's officials.
-- chamber is where the indicator was measured (the Congress chamber, the last legislative chamber served
-- in, or the chamber whose votes were counted), which can differ from the official's current office.
-- detail is a lookup key as well as a caption: the frontend (SectionIdeology) matches each rpt_indicator_peers
-- strip to its indicator row on (indicator, period, detail) and tells a member's two party-unity rows apart by
-- the leading chamber key ("state_house: ..."). Keep the party-unity wording stable; fix other detail text only
-- together with the frontend.
-- first_vote_year / last_vote_year (party unity only, else null) are the official's own first and last calendar
-- year with a dated party-line vote in `chamber`; the frontend puts them in the caption, never in the match key.
-- chamber_data_start_year (party unity only, else null) is the first calendar year with any dated party-line vote
-- for `chamber` in our loaded data (any official); when first_vote_year equals it, the caption says the range
-- starts where our records begin, not where the official's service did. The chamber start comes from the party-line
-- votes of tracked officials (fct_party_unity_yearly), which matches the first roll call in the chamber today.
with nominate as (
    select
        o.official_id,
        'dw_nominate_dim1' as indicator,
        case m.chamber when 'House' then 'us_house' when 'Senate' then 'us_senate' end as chamber,
        m.nominate_dim1 as value,
        m.congress as period,
        'Voteview DW-NOMINATE, ' || m.chamber || ' ' || {{ mogov.ordinal('m.congress') }}
        || ' Congress' as detail,
        'https://voteview.com/person/' || {{ dbt.safe_cast('m.icpsr', dbt.type_string()) }} as source_url,
        cast(null as {{ dbt.type_int() }}) as first_vote_year,
        cast(null as {{ dbt.type_int() }}) as last_vote_year,
        cast(null as {{ dbt.type_int() }}) as chamber_data_start_year
    from {{ ref('dim_official') }} as o
    inner join {{ ref('stg_voteview__members') }} as m on o.bioguide_id = m.bioguide_id
    where m.nominate_dim1 is not null
),

shor as (
    select
        o.official_id,
        'shor_mccarty_np' as indicator,
        case s.last_chamber when 'upper' then 'state_senate' else 'state_house' end as chamber,
        s.np_score as value,
        s.last_year as period,
        -- first/last year come from the dataset's per-year columns, which end at the dataset's last year (2022), so
        -- for current members the end year is that cutoff, not the end of service: say so in the caption.
        'Shor-McCarty career ideal point; in the Shor-McCarty data '
        || {{ dbt.safe_cast('s.first_year', dbt.type_string()) }}
        || '-' || {{ dbt.safe_cast('s.last_year', dbt.type_string()) }}
        || ' (data ends '
        || {{ dbt.safe_cast('d.data_end_year', dbt.type_string()) }}
        || ')' as detail,
        'https://doi.org/10.7910/DVN/SGOQ7G' as source_url,
        cast(null as {{ dbt.type_int() }}) as first_vote_year,
        cast(null as {{ dbt.type_int() }}) as last_vote_year,
        cast(null as {{ dbt.type_int() }}) as chamber_data_start_year
    from {{ ref('stg_shor_mccarty__scores') }} as s
    cross join (select max(last_year) as data_end_year from {{ ref('stg_shor_mccarty__scores') }}) as d
    inner join {{ ref('int_mo_legislators__seats') }} as seat
        on
            s.last_chamber = seat.chamber
            and s.last_district = seat.district_number
            and seat.surname_key = {{ mogov.name_key('s.family_name') }}
            and extract(year from seat.start_date) <= s.last_year
            and extract(year from seat.end_date) >= s.last_year
    inner join {{ ref('dim_official') }} as o on seat.person_id = o.official_id
),

-- party unity: summed from the per-year party-line counts (fct_party_unity_yearly), lifetime only here ----------
unity as (
    select
        y.official_id,
        'party_unity_pct' as indicator,
        y.chamber,
        round(100.0 * sum(y.with_party_votes) / sum(y.party_line_votes), 1) as value,
        cast(null as {{ dbt.type_int() }}) as period,
        y.chamber || ': ' || {{ dbt.safe_cast('sum(y.party_line_votes)', dbt.type_string()) }}
        || ' party-line votes' as detail,
        cast(null as {{ dbt.type_string() }}) as source_url,
        -- the official's own first and last calendar year with a dated party-line vote in this chamber
        cast(min(y.vote_year) as {{ dbt.type_int() }}) as first_vote_year,
        cast(max(y.vote_year) as {{ dbt.type_int() }}) as last_vote_year,
        cast(max(c.data_start_year) as {{ dbt.type_int() }}) as chamber_data_start_year
    from {{ ref('fct_party_unity_yearly') }} as y
    inner join (
        select
            chamber,
            min(vote_year) as data_start_year
        from {{ ref('fct_party_unity_yearly') }}
        group by chamber
    ) as c on y.chamber = c.chamber
    group by y.official_id, y.chamber
)

{% set cols = [
    'official_id', 'indicator', 'chamber', 'value', 'period', 'detail', 'source_url',
    'first_vote_year', 'last_vote_year', 'chamber_data_start_year'
] | join(', ') %}
select {{ cols }} from nominate
union all
select {{ cols }} from shor
union all
select {{ cols }} from unity
