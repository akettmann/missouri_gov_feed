-- NAICS codes on business sites whose first two digits are not a sector in the naics_sectors seed (a malformed
-- code, or a new sector). Warns rather than fails: such sites only fall under "No industry code" in
-- rpt_district_business_industries until the seed is updated.
{{ config(severity='warn') }}
select distinct b.naics_code
from {{ ref('fct_jurisdiction_businesses') }} as b
left join {{ ref('naics_sectors') }} as s on left(b.naics_code, 2) = s.naics_prefix
where
    b.naics_code is not null
    and s.naics_prefix is null
