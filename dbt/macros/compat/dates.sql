{#
  Parse a date string with a format given in strftime notation (%m/%d/%Y, %Y-%m-%d, %B %d, %Y ...).
  Returns NULL on failure. Format strings are translated per backend so models stay portable.
#}
{% macro parse_date(expr, fmt) -%}
    {{ return(adapter.dispatch('parse_date', 'mogov')(expr, fmt)) }}
{%- endmacro %}

{% macro default__parse_date(expr, fmt) -%}
    {%- set pg_fmt = fmt | replace('%Y', 'YYYY') | replace('%m', 'MM') | replace('%d', 'DD') | replace('%B', 'FMMonth') -%}
    to_date({{ expr }}, '{{ pg_fmt }}')
{%- endmacro %}

{% macro duckdb__parse_date(expr, fmt) -%}
    {#- %-m style isn't needed: strptime accepts non-padded numbers for %m/%d -#}
    cast(try_strptime(trim({{ expr }}), '{{ fmt }}') as date)
{%- endmacro %}


{# Whole years between two dates (age, tenure). #}
{% macro years_between(start_date, end_date) -%}
    {{ dbt.datediff(start_date, end_date, 'year') }}
{%- endmacro %}


{# DATE from lower-case text "month d, yyyy" ("july 1, 2022"); the month's first three letters give the month. NULL if the text is NULL. #}
{% macro month_name_date(text_expr) -%}
    {{ dbt.safe_cast(dbt.concat([
        mogov.regex_extract(text_expr, '([0-9]{4})$'),
        "'-'",
        mogov.zero_pad(
            dbt.safe_cast(
                '(' ~ dbt.position(mogov.regex_extract(text_expr, '^([a-z]{3})'), "'janfebmaraprmayjunjulaugsepoctnovdec'") ~ ' + 2) / 3',
                dbt.type_int()
            ),
            2
        ),
        "'-'",
        mogov.zero_pad(mogov.regex_extract(text_expr, '([0-9]{1,2}),'), 2),
    ]), 'date') }}
{%- endmacro %}
