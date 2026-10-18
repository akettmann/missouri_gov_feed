-- "Bias" indicators: measurable lean, not judgments. Each row is one indicator for one official:
--   dw_nominate_dim1   Voteview, Congress. -1 liberal .. +1 conservative (economic dimension).
--   shor_mccarty_np    State legislators, 1993-2022. Negative liberal, positive conservative.
--   acu_rating         American Conservative Union yearly score, 0-100 (one advocacy group's view).
--   party_unity_pct    Share of party-line votes (majority of R vs majority of D) where the official
--                      voted with their own party's majority. Computed from the vote records here.
with nominate as (
    select
        o.official_id,
        'dw_nominate_dim1' as indicator,
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
        s.np_score as value,
        s.last_year as period,
        'Shor-McCarty career ideal point; served ' || {{ dbt.safe_cast('s.first_year', dbt.type_string()) }}
        || '-' || {{ dbt.safe_cast('s.last_year', dbt.type_string()) }} as detail,
        'https://doi.org/10.7910/DVN/SGOQ7G' as source_url
    from {{ ref('stg_shor_mccarty') }} as s
    inner join {{ ref('int_mo_legislators__seats') }} as seat
        on
            s.last_chamber = seat.chamber
            and s.last_district = seat.district_number
            and seat.surname_key = {{ mogov.name_key('s.family_name') }}
            and extract(year from seat.start_date) <= s.last_year
            and extract(year from seat.end_date) >= s.last_year
    inner join {{ ref('dim_official') }} as o on seat.openstates_id = o.official_id
),

acu as (
    select
        o.official_id,
        'acu_rating' as indicator,
        a.rating as value,
        a.year as period,
        'ACU ' || a.chamber || ' district ' || {{ dbt.safe_cast('a.district', dbt.type_string()) }} as detail,
        'http://ratings.conservative.org/people/' || a.acu_id as source_url
    from {{ ref('stg_acu__ratings') }} as a
    inner join {{ ref('int_mo_legislators__seats') }} as seat
        on
            seat.chamber = case a.chamber when 'senate' then 'upper' else 'lower' end
            and a.district = seat.district_number
            and seat.surname_key = {{ mogov.name_key('a.family_name') }}
            and extract(year from seat.start_date) <= a.year
            and extract(year from seat.end_date) >= a.year
    inner join {{ ref('dim_official') }} as o on seat.openstates_id = o.official_id
),

-- party unity ----------------------------------------------------------------------------------------
votes as (
    select
        official_id,
        chamber,
        vote_id,
        vote_cast,
        case
            when party_at_vote like 'Republican%' then 'R'
            when party_at_vote like 'Democrat%' then 'D'
        end as party
    from {{ ref('fct_votes') }}
    where vote_cast in ('yea', 'nay')
),

party_positions as (
    select
        chamber,
        vote_id,
        party,
        case when sum(case when vote_cast = 'yea' then 1 else 0 end) * 2 > count(*) then 'yea' else 'nay' end
            as majority_position
    from votes
    where party is not null
    group by chamber, vote_id, party
),

party_line_votes as (
    select
        r.chamber,
        r.vote_id,
        r.majority_position as r_position,
        d.majority_position as d_position
    from party_positions as r
    inner join party_positions as d on r.chamber = d.chamber and r.vote_id = d.vote_id and d.party = 'D'
    where r.party = 'R' and r.majority_position <> d.majority_position
),

unity as (
    select
        v.official_id,
        'party_unity_pct' as indicator,
        round(100.0 * sum(
            case when v.vote_cast = case v.party when 'R' then p.r_position else p.d_position end then 1 else 0 end
        ) / count(*), 1) as value,
        cast(null as {{ dbt.type_int() }}) as period,
        v.chamber || ': ' || {{ dbt.safe_cast('count(*)', dbt.type_string()) }} || ' party-line votes' as detail,
        cast(null as {{ dbt.type_string() }}) as source_url
    from votes as v
    inner join party_line_votes as p on v.chamber = p.chamber and v.vote_id = p.vote_id
    where v.party is not null
    group by v.official_id, v.chamber
)

{% set cols = 'official_id, indicator, value, period, detail, source_url' %}
select {{ cols }} from nominate
union all
select {{ cols }} from shor
union all
select {{ cols }} from acu
union all
select {{ cols }} from unity
