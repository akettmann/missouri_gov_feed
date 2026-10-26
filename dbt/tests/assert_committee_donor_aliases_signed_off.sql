-- Sanity check (warn): curated donor aliases match at "high" confidence, so each one should be signed off by a
-- maintainer (checked_by and checked_on filled). Until then the build warns instead of failing, so unsigned
-- aliases stay visible without blocking it (#109). Returns one row per committee with unsigned aliases: its
-- name, how many aliases are unsigned, and which ones; a name filled in but no date (or the reverse) counts as
-- unsigned. To sign off, see "Signing off donor aliases" in docs/sources.md.
{{ config(severity='warn') }}

select
    mec_committee_id,
    min(committee_name) as committee_name,
    count(*) as n_unsigned_aliases,
    {{ dbt.listagg('alias', "'; '", 'order by alias') }} as unsigned_aliases
from {{ ref('committee_donor_aliases') }}
where checked_by is null or checked_on is null or trim(checked_by) = ''
group by mec_committee_id
