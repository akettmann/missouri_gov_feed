-- Missouri TIGER/Line boundaries, one row per feature: state senate and house districts, congressional
-- districts (one set per Congress), counties and places. district_number is the district's number for
-- legislative and congressional districts (from the GEOID after the state code); geometry stays GeoJSON text.
{% set layer = mogov.json_str('payload', '$.layer') %}
{% set geoid = mogov.json_str('payload', '$.properties.GEOID') %}

select
    {{ layer }} as layer,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.vintage'), dbt.type_int()) }} as vintage,
    {{ geoid }} as geoid,
    coalesce(
        {{ mogov.json_str('payload', '$.properties.NAME') }},
        {{ mogov.json_str('payload', '$.properties.NAMELSAD') }}
    ) as name,
    {{ mogov.json_str('payload', '$.properties.NAMELSAD') }} as name_with_type,
    case
        when {{ layer }} in ('sldu', 'sldl', 'cd')
            then {{ dbt.safe_cast("substr(" ~ geoid ~ ", 3)", dbt.type_int()) }}
    end as district_number,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.properties.CDSESSN'), dbt.type_int()) }} as congress,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.properties.ALAND'), dbt.type_bigint()) }} as land_area_m2,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.properties.INTPTLAT'), dbt.type_float()) }} as interior_lat,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.properties.INTPTLON'), dbt.type_float()) }} as interior_lon,
    {{ mogov.json_fragment('payload', '$.geometry') }} as geometry_geojson,
    {{ mogov.json_str('payload', '$.file') }} as source_file,
    source_url,
    loaded_at
from {{ source('census_tiger', 'features') }}
