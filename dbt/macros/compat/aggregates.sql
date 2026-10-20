{#
  Median as an aggregate. dbt has no cross-database macro for it; the ordered-set form below works on
  DuckDB, Postgres, Snowflake and Redshift. BigQuery only has it as a window function, so a BigQuery
  backend needs a bigquery__median (e.g. approx_quantiles(expr, 2)[offset(1)]).
#}
{% macro median(expr) -%}
    {{ return(adapter.dispatch('median', 'mogov')(expr)) }}
{%- endmacro %}

{% macro default__median(expr) -%}
    percentile_cont(0.5) within group (order by {{ expr }})
{%- endmacro %}
