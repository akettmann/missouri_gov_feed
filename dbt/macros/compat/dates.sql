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


{#
  The second Monday of January of a year (an integer expression), as a date: the day a Missouri statewide officer's
  regular four-year term begins, at noon. RSMo 27.010 sets this for the Attorney General; the other five offices
  follow the same observed swearing-in practice (2017-01-09, 2019-01-14, 2021-01-11, 2023-01-09, 2025-01-13).
  Portable: no day-of-week function; 1900-01-01 was a Monday, so the days since it, mod 7, say how far January 1
  is past a Monday. dateadd gives a timestamp on DuckDB, so the result is cast back to date.
#}
{% macro second_monday_of_january(year_expr) -%}
    {%- set jan_first = dbt.safe_cast(dbt.concat([dbt.safe_cast(year_expr, dbt.type_string()), "'-01-01'"]), 'date') -%}
    cast({{ dbt.dateadd(
        'day',
        '7 + mod(7 - mod(' ~ dbt.datediff("cast('1900-01-01' as date)", jan_first, 'day') ~ ', 7), 7)',
        jan_first
    ) }} as date)
{%- endmacro %}
