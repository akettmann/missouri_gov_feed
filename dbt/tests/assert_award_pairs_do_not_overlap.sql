-- Sanity check: nobody holds both ends of a paired award (lowest and highest attendance, ...) for the same
-- office and period. Returns the officials that do.
select
    {{ mogov.award_pair_expr('award') }} as pair_key,
    office,
    period,
    official_id,
    count(*) as lists_held
from {{ ref('rpt_awards') }}
where {{ mogov.award_pair_expr('award') }} is not null
group by {{ mogov.award_pair_expr('award') }}, office, period, official_id
having count(*) > 1
