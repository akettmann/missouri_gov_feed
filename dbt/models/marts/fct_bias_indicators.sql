-- "Bias" indicators: measurable lean, not judgments. Each row is one indicator for one official:
--   dw_nominate_dim1   Voteview, Congress. -1 liberal .. +1 conservative (economic dimension).
--   shor_mccarty_np    State legislators, 1993-2022. Negative liberal, positive conservative.
--   party_unity_pct    Share of party-line votes (majority of R vs majority of D) where the official
--                      voted with their own party's majority. Computed from the vote records here; the
--                      majorities count every member who voted, not just today's officials.
-- chamber is where the indicator was measured (the Congress chamber, the last legislative chamber served
-- in, or the chamber whose votes were counted), which can differ from the official's current office.
with nominate as (
    select
        o.official_id,
        'dw_nominate_dim1' as indicator,
        case m.chamber when 'House' then 'us_house' else 'us_senate' end as chamber,
        m.nominate_dim1 as value,
        m.congress as period,
        'Voteview DW-NOMINATE, ' || m.chamber || ' ' || {{ dbt.safe_cast('m.congress', dbt.type_string()) }}
        || 'th Congress' as detail,
        'https://voteview.com/person/' || {{ dbt.safe_cast('m.icpsr', dbt.type_string()) }} as source_url
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
        'Shor-McCarty career ideal point; served ' || {{ dbt.safe_cast('s.first_year', dbt.type_string()) }}
        || '-' || {{ dbt.safe_cast('s.last_year', dbt.type_string()) }} as detail,
        'https://doi.org/10.7910/DVN/SGOQ7G' as source_url
    from {{ ref('stg_shor_mccarty__scores') }} as s
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
        cast(null as {{ dbt.type_string() }}) as source_url
    from {{ ref('fct_party_unity_yearly') }} as y
    group by y.official_id, y.chamber
)

{% set cols = 'official_id, indicator, chamber, value, period, detail, source_url' %}
select {{ cols }} from nominate
union all
select {{ cols }} from shor
union all
select {{ cols }} from unity
