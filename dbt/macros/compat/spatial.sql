{#
  Point-in-polygon for boundaries stored as GeoJSON text (dim_district.geometry_geojson, lon/lat NAD83).
  Geometry types and functions differ per backend. The ones that differ (geom_from_geojson, geom_point,
  geom_buffer) are dispatched per adapter; the rest are plain wrappers because DuckDB's spatial extension
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


{% macro geom_intersects(a, b) -%}
    st_intersects({{ a }}, {{ b }})
{%- endmacro %}


{#
  Area of the overlap of two boundaries, in square degrees (both backends return the planar area of the
  geometry's own coordinates). Callers convert to km2 with the latitude of the area, which is plenty for
  comparing overlaps against a threshold.
#}
{% macro geom_intersection_area(a, b) -%}
    st_area(st_intersection({{ a }}, {{ b }}))
{%- endmacro %}


{% macro geom_intersection(a, b) -%}
    st_intersection({{ a }}, {{ b }})
{%- endmacro %}


{% macro geom_area(geom) -%}
    st_area({{ geom }})
{%- endmacro %}


{#
  Buffer a geometry by `distance` in the geometry's own units (degrees for our lon/lat NAD83 data); negative
  shrinks it. Callers convert metres to degrees themselves (see geom_metres_to_degrees). Dispatched so a backend
  can substitute its own call (e.g. PostGIS geography) without touching models.
#}
{% macro geom_buffer(geom, distance) -%}
    {{ return(adapter.dispatch('geom_buffer', 'mogov')(geom, distance)) }}
{%- endmacro %}

{% macro default__geom_buffer(geom, distance) -%}
    {{ exceptions.raise_compiler_error("geom_buffer: no implementation for " ~ target.type) }}
{%- endmacro %}

{% macro duckdb__geom_buffer(geom, distance) -%}
    st_buffer({{ geom }}, {{ distance }})
{%- endmacro %}

{% macro postgres__geom_buffer(geom, distance) -%}
    st_buffer({{ geom }}, {{ distance }})
{%- endmacro %}


{#
  Metres to degrees of longitude at `lat_expr` (degrees). A degree of longitude is 111,320 m * cos(latitude);
  a degree of latitude is about 110,570 m, so using the longitude figure for an isotropic degree buffer is
  conservative east-west and about 1.3x generous north-south at Missouri's latitudes (the buffer is a margin
  against sliver noise, not a measurement).
#}
{% macro geom_metres_to_degrees(metres, lat_expr) -%}
    ({{ metres }} / (111320.0 * cos(radians({{ lat_expr }}))))
{%- endmacro %}
