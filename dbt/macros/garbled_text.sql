{# Boolean: is expr unreadable OCR output rather than text? For prose fields of scanned forms (AO-10 positions,
   income sources, agreements), not for codes or tickers. Only letters, digits and '=' are counted, so dash
   and underline runs left by the form's ruled lines are ignored. It is garbled when either:
     - more than half of those characters are outside word-like tokens (3+ letters, capitalized or all caps),
       e.g. "2200 =oK00 =o OL00 Es 0. B1=$1,000,001:$5,000,000 + P4=More than $50,000,000", or
     - it has no run of 4 letters, e.g. "SIE = RE", "EE TTT ----".
   Null and blank text is not garbled. Tested against fixed examples in tests/assert_garbled_text.sql. #}
{% macro is_garbled_text(expr) -%}
    {%- set counted = dbt.length(mogov.regex_replace_all(expr, '[^A-Za-z0-9=]', '')) -%}
    {%- set outside_words = dbt.length(mogov.regex_replace_all(
        mogov.regex_replace_all(expr, '[A-Za-z][a-z]{2,}|[A-Z]{3,}', ''), '[^A-Za-z0-9=]', ''
    )) -%}
    coalesce(
        {{ counted }} > 0
        and (2 * {{ outside_words }} > {{ counted }} or not {{ mogov.regex_matches(expr, '[A-Za-z]{4}') }}),
        false
    )
{%- endmacro %}
