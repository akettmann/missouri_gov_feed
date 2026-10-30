{# One row per space-separated word of `expr`, as a FROM-clause join fragment: write
   `from t {{ mogov.cross_join_words('t.text', 'w') }}` and read `w.word` (an empty string for each stray space or
   an empty text; a null text gives no row). The words are split by the database, so there is no upper bound on
   their number (a part-number spine, as in split_part_at, needs one). Postgres and Snowflake dispatches are
   untested against a live backend, like most of this file's non-DuckDB variants. #}
{% macro cross_join_words(expr, alias) -%}
    {{ return(adapter.dispatch('cross_join_words', 'mogov')(expr, alias)) }}
{%- endmacro %}

{% macro default__cross_join_words(expr, alias) -%}
    cross join lateral unnest(string_to_array({{ expr }}, ' ')) as {{ alias }} (word)
{%- endmacro %}

{% macro duckdb__cross_join_words(expr, alias) -%}
    cross join unnest(string_split({{ expr }}, ' ')) as {{ alias }} (word)
{%- endmacro %}

{% macro snowflake__cross_join_words(expr, alias) -%}
    cross join lateral split_to_table({{ expr }}, ' ') as {{ alias }} (seq, idx, word)
{%- endmacro %}
