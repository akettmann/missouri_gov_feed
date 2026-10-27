{{ config(severity='warn') }}
-- A House full committee's discharged_date can be its subcommittee's discharge (Congress.gov records it under the
-- parent too), so a full-committee row discharged and then marked up or reported later is a known pattern, not an
-- error: 21 of 115 on the 118th hr and s (2026-10-27). Warn when it grows past 60, which would mean the source
-- records more of these (or the discharged_date column should stop being read as the committee's own discharge).
select count(*) as discharged_then_acted_rows
from {{ ref('fct_federal_sponsorship_committees') }}
where
    not is_subcommittee
    and discharged_date is not null
    and (markup_date > discharged_date or reported_date > discharged_date)
having count(*) > 60
