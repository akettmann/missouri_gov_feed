-- Sanity check (warn): curated donor aliases match at "high" confidence, so each one should be signed off by a
-- maintainer (checked_by and checked_on filled). Until then the build warns instead of failing, so unsigned
-- aliases stay visible without blocking it (#109). Returns one row per committee with unsigned aliases, with how
-- many of its aliases are unsigned; a name filled in but no date (or the reverse) counts as unsigned.
{{ config(severity='warn') }}

select
    mec_committee_id,
    count(*) as n_unsigned_aliases
from {{ ref('committee_donor_aliases') }}
where checked_by is null or checked_on is null or trim(checked_by) = ''
group by mec_committee_id
