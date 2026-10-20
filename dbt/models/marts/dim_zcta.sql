-- Missouri ZIP Code Tabulation Areas for "find my officials by ZIP": each ZCTA's internal point and land area.
-- Missouri's ZIP prefixes are 630-658 (USPS); a ZCTA that crosses into a neighboring state keeps its whole
-- area here, and the frontend only matches points that fall inside Missouri districts.
select
    zcta,
    vintage,
    interior_lat,
    interior_lon,
    land_area_m2,
    water_area_m2
from {{ ref('stg_census_zcta__gazetteer') }}
where zcta >= '63000' and zcta < '65900'
