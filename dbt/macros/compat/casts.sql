{#
  dbt.safe_cast() on dbt-duckdb is a plain CAST, which raises on bad input (e.g. '' -> int).
  Make it NULL-on-failure like Snowflake/BigQuery/Postgres-with-guards. Models keep calling
  dbt.safe_cast(); the dispatch search order in dbt_project.yml routes DuckDB here.
#}
{% macro duckdb__safe_cast(field, type) -%}
    try_cast({{ field }} as {{ type }})
{%- endmacro %}
