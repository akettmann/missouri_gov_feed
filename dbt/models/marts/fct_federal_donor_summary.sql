-- Federal campaign totals per member per cycle (FEC candidate summary), plus their top itemized donor
-- employers / size buckets / states (FEC API aggregates; present when FEC_API_KEY is configured).
with ids as (
    select
        o.official_id,
        f.fec_candidate_id
    from {{ ref('dim_official') }} as o
    inner join {{ ref('stg_congress__fec_ids') }} as f on o.bioguide_id = f.bioguide_id
),

{% set metrics = [
    ('total receipts', 's.total_receipts'),
    ('individual contributions', 's.individual_contributions'),
    ('PAC contributions', 's.pac_contributions'),
    ('party contributions', 's.party_contributions'),
    ('candidate self-funding', 'coalesce(s.candidate_self_contributions, 0) + coalesce(s.candidate_loans, 0)'),
    ('total disbursements', 's.total_disbursements'),
    ('cash on hand (end)', 's.cash_on_hand_end'),
] %}
totals as (
    {% for label, expr in metrics %}
        select
            i.official_id,
            s.cycle,
            'cycle total' as aggregate_kind,
            '{{ label }}' as bucket,
            {{ expr }} as total,
            cast(null as {{ dbt.type_int() }}) as contribution_count
        from ids as i
        inner join {{ ref('stg_fec__candidate_summary') }} as s on i.fec_candidate_id = s.candidate_id
        {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

aggregates as (
    select
        i.official_id,
        a.cycle,
        a.aggregate_kind,
        a.bucket,
        a.total,
        a.contribution_count
    from ids as i
    inner join {{ ref('stg_fec__receipt_aggregates') }} as a on i.fec_candidate_id = a.candidate_id
)

select * from totals
union all
select * from aggregates
