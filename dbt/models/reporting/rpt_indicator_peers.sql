-- Each bias indicator value next to the same measure for the official's peers, for strip charts.
-- A peer group is every tracked official with the same indicator measured in the same chamber (and, for
-- DW-NOMINATE, the same Congress, since its scale is per-Congress). Shor-McCarty is a career score and party
-- unity covers all loaded votes, so those group on chamber alone. Medians, not means: one outlier shouldn't
-- move the comparison. No ranks or percentiles, by design: the frontend shows the distribution instead.
with indicators as (
    select
        b.official_id,
        o.full_name,
        o.party,
        b.indicator,
        b.chamber,
        b.period,
        b.detail,
        b.value,
        b.source_url,
        b.indicator || ':' || b.chamber
        || case
            when b.indicator = 'dw_nominate_dim1' then ':' || {{ dbt.safe_cast('b.period', dbt.type_string()) }}
            else ''
        end as peer_group
    from {{ ref('fct_bias_indicators') }} as b
    inner join {{ ref('dim_official') }} as o on b.official_id = o.official_id
    where b.value is not null
),

peer_stats as (
    select
        peer_group,
        count(*) as peer_count,
        {{ mogov.median('value') }} as peer_median,
        min(value) as peer_min,
        max(value) as peer_max
    from indicators
    group by peer_group
),

party_stats as (
    select
        peer_group,
        party,
        count(*) as party_peer_count,
        {{ mogov.median('value') }} as party_median
    from indicators
    where party is not null
    group by peer_group, party
)

select
    i.official_id,
    i.full_name,
    i.party,
    i.indicator,
    i.chamber,
    i.period,
    i.detail,
    i.value,
    i.peer_group,
    p.peer_count,
    p.peer_median,
    p.peer_min,
    p.peer_max,
    own.party_peer_count,
    own.party_median,
    r.party_median as republican_median,
    d.party_median as democratic_median,
    i.source_url
from indicators as i
inner join peer_stats as p on i.peer_group = p.peer_group
left join party_stats as own on i.peer_group = own.peer_group and i.party = own.party
left join party_stats as r on i.peer_group = r.peer_group and r.party = 'Republican'
left join party_stats as d on i.peer_group = d.peer_group and d.party = 'Democratic'
