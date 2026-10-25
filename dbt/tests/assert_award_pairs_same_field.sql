-- Sanity check: the two awards of a pair rank one number over one field, so both have the same group_size for
-- an office and period (a pair of a dollar award with a share award, which rank different officials, would not).
-- Returns the (pair, office, period) where the two ends disagree.
select
    {{ mogov.award_pair_expr('award') }} as pair_key,
    office,
    period,
    min(group_size) as min_group_size,
    max(group_size) as max_group_size
from {{ ref('rpt_awards') }}
where {{ mogov.award_pair_expr('award') }} is not null
group by {{ mogov.award_pair_expr('award') }}, office, period
having min(group_size) != max(group_size)
