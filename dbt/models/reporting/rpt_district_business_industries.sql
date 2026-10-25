-- EPA-regulated business sites in each district-elected official's area (fct_jurisdiction_businesses), counted
-- by NAICS sector (first two digits of naics_code: the site's NAICS code, or for a site with only a SIC code the
-- NAICS sector that SIC code maps to), with how many of them are tied to a donor. A house district can hold
-- 1,400 sites and a U.S. House district 10,000, too many to list on a page; the donor sites themselves come
-- from the mart. Sites with neither code (about 44%) are counted under "No industry code".
select
    b.official_id,
    s.sector_code,
    cast(coalesce(min(s.sector_name), 'No industry code') as {{ dbt.type_string() }}) as sector_name,
    cast(count(*) as {{ dbt.type_bigint() }}) as n_sites,
    cast(sum(case when b.is_donor then 1 else 0 end) as {{ dbt.type_bigint() }}) as n_donor_sites
from {{ ref('fct_jurisdiction_businesses') }} as b
left join {{ ref('naics_sectors') }} as s on left(b.naics_code, 2) = s.naics_prefix
group by b.official_id, s.sector_code
