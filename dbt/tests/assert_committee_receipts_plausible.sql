-- No Missouri committee takes in an absurd amount. Measured October 2026 (int_mec__contributions_received,
-- both feeds): the largest year for one committee is $45.6M (C242679, 2024, a ballot-measure committee funded
-- by 30 large gifts); the largest single itemized gift is $5M. Fails at $150M for a committee in a year or $25M
-- in one gift, which would mean a units, parsing or duplication error (e.g. amended reports counted twice).
with by_year as (
    select
        mec_committee_id,
        contribution_year,
        sum(amount) as total_amount,
        max(amount) as largest_gift
    from {{ ref('int_mec__contributions_received') }}
    group by mec_committee_id, contribution_year
)

select
    mec_committee_id,
    contribution_year,
    total_amount,
    largest_gift
from by_year
where total_amount > 150000000 or largest_gift > 25000000
