-- Federal campaign totals per member per cycle (FEC candidate summary), plus their top itemized donor
-- employers / size buckets / states (FEC API aggregates; present when FEC_API_KEY is configured).
-- Members can have several FEC candidate ids (a House and a Senate run, or a re-registration) that FEC
-- reports against the same committee, with identical figures. Identical rows are collapsed before
-- genuinely separate campaigns are summed, so nothing is counted twice.
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
    -- distinct: the same committee reported under two candidate ids yields identical rows
    select distinct
        official_id,
        cycle,
        aggregate_kind,
        bucket,
        total,
        contribution_count
    from (
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
    ) as per_candidate
),

aggregates as (
    -- one copy per committee, however many of the member's candidate ids it was fetched under
    select distinct
        i.official_id,
        a.committee_id,
        a.cycle,
        a.aggregate_kind,
        a.bucket,
        a.total,
        a.contribution_count
    from ids as i
    inner join {{ ref('stg_fec__receipt_aggregates') }} as a on i.fec_candidate_id = a.candidate_id
)

select
    official_id,
    cycle,
    aggregate_kind,
    bucket,
    sum(total) as total,
    sum(contribution_count) as contribution_count
from (
    select
        official_id,
        cycle,
        aggregate_kind,
        bucket,
        total,
        contribution_count
    from totals
    union all
    select
        official_id,
        cycle,
        aggregate_kind,
        bucket,
        total,
        contribution_count
    from aggregates
) as rows_
group by 1, 2, 3, 4
