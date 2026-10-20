{#
  Point-in-polygon for boundaries stored as GeoJSON text (dim_district.geometry_geojson, lon/lat NAD83).
  Geometry types and functions differ per backend, so they are dispatched: DuckDB's spatial extension
  (loaded in profiles.yml) and PostGIS take the same ST_ names. A model builds the geometries in a CTE,
  joins on geom_contains, and selects no geometry column, so no table stores a backend-specific type.
#}
{% macro geom_from_geojson(expr) -%}
    {{ return(adapter.dispatch('geom_from_geojson', 'mogov')(expr)) }}
{%- endmacro %}

{% macro default__geom_from_geojson(expr) -%}
    {{ exceptions.raise_compiler_error("geom_from_geojson: no implementation for " ~ target.type) }}
{%- endmacro %}

{% macro duckdb__geom_from_geojson(expr) -%}
    st_geomfromgeojson({{ expr }})
{%- endmacro %}

{% macro postgres__geom_from_geojson(expr) -%}
    st_setsrid(st_geomfromgeojson({{ expr }}), 4269)
{%- endmacro %}


{% macro geom_point(lon, lat) -%}
    {{ return(adapter.dispatch('geom_point', 'mogov')(lon, lat)) }}
{%- endmacro %}

{% macro default__geom_point(lon, lat) -%}
    {{ exceptions.raise_compiler_error("geom_point: no implementation for " ~ target.type) }}
{%- endmacro %}

{% macro duckdb__geom_point(lon, lat) -%}
    st_point({{ lon }}, {{ lat }})
{%- endmacro %}

{% macro postgres__geom_point(lon, lat) -%}
    st_setsrid(st_makepoint({{ lon }}, {{ lat }}), 4269)
{%- endmacro %}


{% macro geom_contains(area, point) -%}
    st_contains({{ area }}, {{ point }})
{%- endmacro %}
