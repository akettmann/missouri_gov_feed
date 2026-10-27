-- most_bills_passed_house ranks a percentage over decided sponsored bills: it must be 0-100, rest on at least
-- awards_min_bills_decided bills, and no period may rest on an absurd number of bills (the busiest member-year
-- loaded has about 60 House sponsorships; lifetime spans several sessions, so it gets a higher ceiling).
select
    award,
    office,
    period,
    official_id,
    metric,
    sample_size
from {{ ref('rpt_awards') }}
where
    award = 'most_bills_passed_house'
    and (
        office <> 'state_house'
        or metric < 0
        or metric > 100
        or sample_size < {{ var('awards_min_bills_decided') }}
        or sample_size > case when period = 'lifetime' then 600 else 150 end
    )
