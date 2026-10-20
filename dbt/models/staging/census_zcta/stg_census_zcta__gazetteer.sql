-- Census Gazetteer ZIP Code Tabulation Areas, one row per ZCTA nationwide: the five-digit code, land and water
-- area, and the internal point (a point inside the area, near its center). vintage comes from the file name
-- (2026_Gaz_zcta_national.txt).
select
    geoid as zcta,
    {{ dbt.safe_cast('aland', dbt.type_bigint()) }} as land_area_m2,
    {{ dbt.safe_cast('awater', dbt.type_bigint()) }} as water_area_m2,
    {{ dbt.safe_cast('intptlat', dbt.type_float()) }} as interior_lat,
    {{ dbt.safe_cast('intptlong', dbt.type_float()) }} as interior_lon,
    {{ dbt.safe_cast(dbt.split_part(dbt.right('filename', 26), "'_'", 1), dbt.type_int()) }} as vintage
from {{ source('census_zcta', 'gazetteer') }}
