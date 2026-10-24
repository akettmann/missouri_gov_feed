-- Number-based "awards": the top officials (5 unless the awards_threshold var says otherwise) on one measured
-- number, within one office (House members against House members), per calendar year and over all loaded
-- years, each paired with its opposite. streak_years counts consecutive qualifying yearly periods.
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
),

thresholds as (
    -- per-award cutoff from the awards_threshold var (dbt_project.yml); awards not listed use its default
    select
        award,
        office,
        period,
        official_id,
        metric,
        sample_size,
        award_rank,
        group_size,
        case
            -- keeps the case valid when the var lists no award of its own
            when award is null then {{ var('awards_threshold')['default'] }}
            {%- for award_name, cutoff in var('awards_threshold').items() if award_name != 'default' %}
            when award = '{{ award_name }}' then {{ cutoff }}
            {%- endfor %}
            else {{ var('awards_threshold')['default'] }}
        end as threshold
    from ranked
    -- a ranking needs a field: single-seat offices (governor) and thin years are left out entirely, which is
    -- also why they neither add to nor break a streak
    where group_size >= {{ var('awards_min_field_size') }}
),

yearly as (
    select
        award,
        office,
        period,
        official_id,
        case when award_rank <= threshold then 1 else 0 end as qualifies,
        -- failed years so far (ranked but outside the threshold); each one starts a new run of qualifying years
        sum(case when award_rank <= threshold then 0 else 1 end) over (
            partition by award, office, official_id
            order by period
            rows between unbounded preceding and current row
        ) as failures_so_far
    from thresholds
    where period <> 'lifetime'
),

streaks as (
    select
        award,
        office,
        period,
        official_id,
        qualifies,
        sum(qualifies) over (
            partition by award, office, official_id, failures_so_far
            order by period
            rows between unbounded preceding and current row
        ) as streak_years
    from yearly
)

select
    cast(t.award as {{ dbt.type_string() }}) as award,
    cast(t.office as {{ dbt.type_string() }}) as office,
    cast(t.period as {{ dbt.type_string() }}) as period,
    cast(t.award_rank as {{ dbt.type_bigint() }}) as award_rank,
    cast(t.official_id as {{ dbt.type_string() }}) as official_id,
    cast(t.metric as {{ dbt.type_numeric() }}) as metric,
    cast(t.sample_size as {{ dbt.type_numeric() }}) as sample_size,
    cast(t.group_size as {{ dbt.type_bigint() }}) as group_size,
    -- null for lifetime rows: only yearly periods make a streak
    cast(s.streak_years as {{ dbt.type_bigint() }}) as streak_years
from thresholds as t
left join streaks as s
    on
        t.award = s.award
        and t.office = s.office
        and t.period = s.period
        and t.official_id = s.official_id
where t.award_rank <= t.threshold
