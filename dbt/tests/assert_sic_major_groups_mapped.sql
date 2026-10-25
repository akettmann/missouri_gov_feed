-- SIC major groups (first two digits) that EPA FRS gives a facility but the sic_naics_sectors seed has no row for
-- (a new group, or a malformed code). Warns rather than fails: such facilities only fall under "No industry
-- code" until the seed is updated. Group 99 (nonclassifiable establishments) is deliberately unmapped.
{{ config(severity='warn') }}
select distinct left(s.sic_code, 2) as sic_major_group
from {{ ref('stg_epa_frs__sic') }} as s
left join {{ ref('sic_naics_sectors') }} as m on left(s.sic_code, 2) = left(m.sic_prefix, 2)
where
    s.sic_code is not null
    and left(s.sic_code, 2) <> '99'
    and m.sic_prefix is null
