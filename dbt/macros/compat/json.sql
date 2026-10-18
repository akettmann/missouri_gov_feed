{#
  Backend-portable JSON access. Paths are SQL/JSON standard ('$.a.b', '$.a[0].b').
  default__ uses the SQL:2016 standard functions (JSON_VALUE / JSON_QUERY / JSON_TABLE), which
  Oracle, SQL Server, BigQuery (JSON_VALUE/JSON_QUERY) and Postgres 17+ implement; postgres__ uses
  jsonb_path functions for older Postgres. Add an adapter__ variant here when moving to a backend
  that needs one -- models never call backend JSON functions directly.
#}

{# Scalar at path, as a string (NULL when missing). #}
{% macro json_str(expr, path) -%}
    {{ return(adapter.dispatch('json_str', 'mogov')(expr, path)) }}
{%- endmacro %}

{% macro default__json_str(expr, path) -%}
    json_value({{ expr }}, '{{ path }}')
{%- endmacro %}

{% macro duckdb__json_str(expr, path) -%}
    json_extract_string({{ expr }}, '{{ path }}')
{%- endmacro %}

{% macro postgres__json_str(expr, path) -%}
    (jsonb_path_query_first(cast({{ expr }} as jsonb), '{{ path }}') #>> '{}')
{%- endmacro %}


{# JSON fragment (object/array) at path, as JSON text. #}
{% macro json_fragment(expr, path) -%}
    {{ return(adapter.dispatch('json_fragment', 'mogov')(expr, path)) }}
{%- endmacro %}

{% macro default__json_fragment(expr, path) -%}
    json_query({{ expr }}, '{{ path }}')
{%- endmacro %}

{% macro duckdb__json_fragment(expr, path) -%}
    cast(json_extract({{ expr }}, '{{ path }}') as varchar)
{%- endmacro %}

{% macro postgres__json_fragment(expr, path) -%}
    cast(jsonb_path_query_first(cast({{ expr }} as jsonb), '{{ path }}') as text)
{%- endmacro %}


{#
  Explode the JSON array at path into rows. Use as a lateral join:
      from people as p
      cross join lateral {{ mogov.json_elements('p.doc', '$.roles') }} as r
  r.value is each element (JSON text), r.idx its 1-based position. Rows whose array is missing or
  empty drop out, as with any inner lateral join.
#}
{% macro json_elements(expr, path) -%}
    {{ return(adapter.dispatch('json_elements', 'mogov')(expr, path)) }}
{%- endmacro %}

{% macro default__json_elements(expr, path) -%}
    json_table({{ expr }}, '{{ path }}[*]' columns (
        idx for ordinality,
        value varchar(32000) format json path '$'
    ))
{%- endmacro %}

{% macro duckdb__json_elements(expr, path) -%}
    (
        select
            cast(unnest(from_json(json_extract({{ expr }}, '{{ path }}'), '["json"]')) as varchar) as value,
            generate_subscripts(from_json(json_extract({{ expr }}, '{{ path }}'), '["json"]'), 1) as idx
    )
{%- endmacro %}

{% macro postgres__json_elements(expr, path) -%}
    (
        select cast(e.value as text) as value, e.idx
        from jsonb_array_elements(jsonb_path_query_first(cast({{ expr }} as jsonb), '{{ path }}'))
            with ordinality as e (value, idx)
    )
{%- endmacro %}
