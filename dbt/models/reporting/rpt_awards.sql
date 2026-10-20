-- Number-based "awards": the top 5 officials on one measured number, within one office (House members
-- against House members), per calendar year and over all loaded years, each paired with its opposite.
-- Every award ranks a single figure that the profile pages also show; nothing is combined into a score.
--   attendance:        rpt_attendance, present / recorded votes, at least 100 recorded votes in the period
--   committee money:   rpt_donor_rollup from PACs, committees and parties (medium name matches left out);
--                      the opposite ranks the lowest share of such money among officials raising $10,000+
--   party unity:       fct_bias_indicators party_unity_pct for the official's current chamber; the source
--                      computes it over all loaded votes, so it has a lifetime period only
with offices as (
    select
        official_id,
        office
    from {{ ref('dim_official') }}
),

attendance_years as (
    select
        official_id,
        cast(extract(year from first_vote_date) as {{ dbt.type_string() }}) as period,
        sum(votes_present) as present,
        sum(votes_recorded) as recorded
    from {{ ref('rpt_attendance') }}
    group by official_id, cast(extract(year from first_vote_date) as {{ dbt.type_string() }})
),

attendance as (
    select
        official_id,
        period,
        present,
        recorded
    from attendance_years
    union all
    select
        official_id,
        'lifetime' as period,
        sum(present) as present,
        sum(recorded) as recorded
    from attendance_years
    group by official_id
),

attendance_rates as (
    select
        a.official_id,
        o.office,
        a.period,
        round(100.0 * a.present / a.recorded, 1) as metric,
        a.recorded as sample_size
    from attendance as a
    inner join offices as o on a.official_id = o.official_id
    where a.recorded >= 100
),

money_years as (
    select
        official_id,
        cast(transaction_year as {{ dbt.type_string() }}) as period,
        sum(
            case when donor_class in ('pac', 'committee', 'candidate committee', 'party') then total_amount else 0 end
        ) as committee_money,
        sum(total_amount) as all_money
    from {{ ref('rpt_donor_rollup') }}
    where match_confidence <> 'medium'
    group by official_id, cast(transaction_year as {{ dbt.type_string() }})
),

money as (
    select
        official_id,
        period,
        committee_money,
        all_money
    from money_years
    union all
    select
        official_id,
        'lifetime' as period,
        sum(committee_money) as committee_money,
        sum(all_money) as all_money
    from money_years
    group by official_id
),

money_with_office as (
    select
        m.official_id,
        o.office,
        m.period,
        m.committee_money,
        m.all_money
    from money as m
    inner join offices as o on m.official_id = o.official_id
),

unity as (
    select
        b.official_id,
        o.office,
        'lifetime' as period,
        b.value as metric
    from {{ ref('fct_bias_indicators') }} as b
    inner join offices as o on b.official_id = o.official_id
    where
        b.indicator = 'party_unity_pct'
        and b.value is not null
        and {{ dbt.split_part('b.detail', "':'", 1) }} = o.office
),

measures as (
    select
        'lowest_attendance' as award,
        official_id,
        office,
        period,
        metric,
        sample_size,
        metric as sort_key
    from attendance_rates
    union all
    select
        'highest_attendance' as award,
        official_id,
        office,
        period,
        metric,
        sample_size,
        -metric as sort_key
    from attendance_rates
    union all
    select
        'most_committee_money' as award,
        official_id,
        office,
        period,
        committee_money as metric,
        all_money as sample_size,
        -committee_money as sort_key
    from money_with_office
    where committee_money > 0
    union all
    select
        'least_committee_money_share' as award,
        official_id,
        office,
        period,
        round(100.0 * committee_money / all_money, 1) as metric,
        all_money as sample_size,
        100.0 * committee_money / all_money as sort_key
    from money_with_office
    where all_money >= 10000
    union all
    select
        'most_party_breaks' as award,
        official_id,
        office,
        period,
        metric,
        null as sample_size,
        metric as sort_key
    from unity
    union all
    select
        'most_party_loyal' as award,
        official_id,
        office,
        period,
        metric,
        null as sample_size,
        -metric as sort_key
    from unity
),

ranked as (
    select
        award,
        official_id,
        office,
        period,
        metric,
        sample_size,
        rank() over (partition by award, office, period order by sort_key) as award_rank,
        count(*) over (partition by award, office, period) as group_size
    from measures
)

select
    cast(award as {{ dbt.type_string() }}) as award,
    cast(office as {{ dbt.type_string() }}) as office,
    cast(period as {{ dbt.type_string() }}) as period,
    cast(award_rank as {{ dbt.type_bigint() }}) as award_rank,
    cast(official_id as {{ dbt.type_string() }}) as official_id,
    cast(metric as {{ dbt.type_numeric() }}) as metric,
    cast(sample_size as {{ dbt.type_numeric() }}) as sample_size,
    cast(group_size as {{ dbt.type_bigint() }}) as group_size
from ranked
-- a ranking needs a field: single-seat offices (governor) and thin years are left out
where award_rank <= 5 and group_size >= 5
