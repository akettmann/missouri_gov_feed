-- Party unity awards rank a percentage over party-line votes: it must be 0-100, rest on at least the
-- awards_min_party_line_votes votes, and no period may rest on an absurd number of votes (the busiest
-- official-year loaded has about 600; lifetime spans many years, so it gets a higher ceiling).
select
    award,
    office,
    period,
    official_id,
    metric,
    sample_size
from {{ ref('rpt_awards') }}
where
    award in ('most_party_breaks', 'most_party_loyal')
    and (
        metric < 0
        or metric > 100
        or sample_size < {{ var('awards_min_party_line_votes') }}
        or sample_size > case when period = 'lifetime' then 20000 else 2000 end
    )
