{# Backend-portable regex and string helpers. Patterns are POSIX-ish; avoid backend-specific escapes. #}

{# Capture group `group` of the first match, or NULL. #}
{% macro regex_extract(expr, pattern, group=1) -%}
    {{ return(adapter.dispatch('regex_extract', 'mogov')(expr, pattern, group)) }}
{%- endmacro %}

{% macro default__regex_extract(expr, pattern, group) -%}
    regexp_substr({{ expr }}, '{{ pattern | replace("'", "''") }}', 1, 1, 'e', {{ group }})
{%- endmacro %}

{% macro duckdb__regex_extract(expr, pattern, group) -%}
    nullif(regexp_extract({{ expr }}, '{{ pattern | replace("'", "''") }}', {{ group }}), '')
{%- endmacro %}

{% macro postgres__regex_extract(expr, pattern, group) -%}
    (regexp_match({{ expr }}, '{{ pattern | replace("'", "''") }}'))[{{ group }}]
{%- endmacro %}


{# Boolean: does the pattern match ANYWHERE in expr (substring semantics, case-sensitive)?
   This is the DuckDB regexp_matches / Postgres `~` behavior. Anchor explicitly (^...$) to require a whole-string match.
   Do not use regexp_like in the default: on Snowflake (and Oracle/MySQL) it is implicitly anchored to the whole
   string, so '[A-Za-z0-9]' would only match one-character strings (#69). regexp_instr returns the 1-based match
   position (0 for none), is unanchored everywhere it exists, and is NULL for NULL input like the others. #}
{% macro regex_matches(expr, pattern) -%}
    {{ return(adapter.dispatch('regex_matches', 'mogov')(expr, pattern)) }}
{%- endmacro %}

{% macro default__regex_matches(expr, pattern) -%}
    (regexp_instr({{ expr }}, '{{ pattern | replace("'", "''") }}') > 0)
{%- endmacro %}

{% macro snowflake__regex_matches(expr, pattern) -%}
    (regexp_instr({{ expr }}, '{{ pattern | replace("'", "''") }}') > 0)
{%- endmacro %}

{% macro duckdb__regex_matches(expr, pattern) -%}
    regexp_matches({{ expr }}, '{{ pattern | replace("'", "''") }}')
{%- endmacro %}

{% macro postgres__regex_matches(expr, pattern) -%}
    ({{ expr }} ~ '{{ pattern | replace("'", "''") }}')
{%- endmacro %}


{# Replace every match of pattern. #}
{% macro regex_replace_all(expr, pattern, replacement) -%}
    {{ return(adapter.dispatch('regex_replace_all', 'mogov')(expr, pattern, replacement)) }}
{%- endmacro %}

{% macro default__regex_replace_all(expr, pattern, replacement) -%}
    regexp_replace({{ expr }}, '{{ pattern | replace("'", "''") }}', '{{ replacement | replace("'", "''") }}')
{%- endmacro %}

{% macro duckdb__regex_replace_all(expr, pattern, replacement) -%}
    regexp_replace({{ expr }}, '{{ pattern | replace("'", "''") }}', '{{ replacement | replace("'", "''") }}', 'g')
{%- endmacro %}

{% macro postgres__regex_replace_all(expr, pattern, replacement) -%}
    regexp_replace({{ expr }}, '{{ pattern | replace("'", "''") }}', '{{ replacement | replace("'", "''") }}', 'g')
{%- endmacro %}


{# Capitalize the first letter of each word. initcap() is standard-ish; DuckDB lacks it. #}
{% macro title_case(expr) -%}
    {{ return(adapter.dispatch('title_case', 'mogov')(expr)) }}
{%- endmacro %}

{% macro default__title_case(expr) -%}
    initcap({{ expr }})
{%- endmacro %}

{% macro duckdb__title_case(expr) -%}
    array_to_string(list_transform(string_split(lower({{ expr }}), ' '), w -> upper(w[1]) || w[2:]), ' ')
{%- endmacro %}


{# Normalize a person/org name for matching: lower-case, letters/digits/spaces only, single spaces. #}
{% macro name_key(expr) -%}
    trim({{ mogov.regex_replace_all(mogov.regex_replace_all('lower(' ~ expr ~ ')', '[^a-z0-9 ]', ' '), ' +', ' ') }})
{%- endmacro %}


{# name_key of a company name without a leading "the" and trailing legal-form words, so "The Doe Company, Inc."
   and "DOE CO" both give "doe". #}
{% macro company_key(expr) -%}
    {{ mogov.regex_replace_all(
        mogov.regex_replace_all(mogov.name_key(expr), '^the ', ''),
        '( (inc|incorporated|llc|l l c|co|corp|corporation|company|companies|ltd|limited|lp|llp|pc|pllc))+$',
        ''
    ) }}
{%- endmacro %}


{# Left-pad with zeros to width n (lpad isn't universal). #}
{% macro zero_pad(expr, n) -%}
    {{ dbt.right(dbt.concat(["'" ~ ('0' * n) ~ "'", dbt.safe_cast(expr, dbt.type_string())]), n) }}
{%- endmacro %}
