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


{#
  Axis-aligned rectangle polygon (st_makeenvelope exists in DuckDB spatial and PostGIS). PostGIS needs the
  SRID to match the other geometry, so the postgres variant stamps 4269 like geom_point.
#}
{% macro geom_envelope(xmin, ymin, xmax, ymax) -%}
    {{ return(adapter.dispatch('geom_envelope', 'mogov')(xmin, ymin, xmax, ymax)) }}
{%- endmacro %}

{% macro default__geom_envelope(xmin, ymin, xmax, ymax) -%}
    {{ exceptions.raise_compiler_error("geom_envelope: no implementation for " ~ target.type) }}
{%- endmacro %}

{% macro duckdb__geom_envelope(xmin, ymin, xmax, ymax) -%}
    st_makeenvelope({{ xmin }}, {{ ymin }}, {{ xmax }}, {{ ymax }})
{%- endmacro %}

{% macro postgres__geom_envelope(xmin, ymin, xmax, ymax) -%}
    st_setsrid(st_makeenvelope({{ xmin }}, {{ ymin }}, {{ xmax }}, {{ ymax }}), 4269)
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
  Metres to degrees for an inward buffer at latitude `lat` (a column or number, in degrees). A degree of longitude
  is 111,320 m * cos(latitude), the shorter of the two degree lengths (about 87,700 m at Missouri's latitudes).
  One degree distance has to serve both axes, so this divides by the longitude length: the buffer then erodes at
  least `metres` in every direction (exactly that east-west, about 1.27x of it north-south), so a kept overlap
  always contains a circle of radius `metres`. The buffer is a margin against sliver noise, not a measurement.
#}
{% macro geom_metres_to_degrees(metres, lat) -%}
    ({{ metres }} / (111320.0 * cos(radians({{ lat }}))))
{%- endmacro %}
