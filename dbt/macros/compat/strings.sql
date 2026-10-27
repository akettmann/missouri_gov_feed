{# Backend-portable regex and string helpers.

   Supported adapters: DuckDB (the tested target, via dbt-duckdb) is the only supported backend. The regex macros
   also have Postgres and Snowflake dispatches (rendered SQL pinned by tests/test_regex_macros.py); other compat macros
   (spatial, JSON) lack Snowflake dispatches. Which adapters to support is open in #121. Trino/Athena (no
   regexp_instr), Spark < 3.3 and anything else are NOT supported: the default__ regex macros assume Snowflake-style
   regexp_substr / regexp_instr.

   Write patterns as plain POSIX ERE: no (?:...), lazy quantifiers, backslash-b/d/s/w classes or lookarounds
   (existing exceptions tracked in #110).
   regex_literal() renders a pattern as a SQL string literal per adapter. Write a literal backslash as two
   backslashes in a Jinja string (Jinja unescapes it to one); the macros do the rest, so callers never think
   about the target's quoting rules. #}

{# SQL string literal for a regex pattern or replacement. Doubles single quotes everywhere. Snowflake string literals
   also treat backslash as an escape character, so a backslash-dot would reach the regex engine as `.`; double it there.
   DuckDB and Postgres (standard_conforming_strings) keep backslashes literally. #}
{% macro regex_literal(text) -%}
    {{ return(adapter.dispatch('regex_literal', 'mogov')(text)) }}
{%- endmacro %}

{% macro default__regex_literal(text) -%}
    '{{ text | replace("'", "''") }}'
{%- endmacro %}

{% macro snowflake__regex_literal(text) -%}
    '{{ text | replace("\\", "\\\\") | replace("'", "''") }}'
{%- endmacro %}

{# Capture group `group` of the first match, or NULL. #}
{% macro regex_extract(expr, pattern, group=1) -%}
    {{ return(adapter.dispatch('regex_extract', 'mogov')(expr, pattern, group)) }}
{%- endmacro %}

{% macro default__regex_extract(expr, pattern, group) -%}
    regexp_substr({{ expr }}, {{ mogov.regex_literal(pattern) }}, 1, 1, 'e', {{ group }})
{%- endmacro %}

{% macro snowflake__regex_extract(expr, pattern, group) -%}
    regexp_substr({{ expr }}, {{ mogov.regex_literal(pattern) }}, 1, 1, 'e', {{ group }})
{%- endmacro %}

{% macro duckdb__regex_extract(expr, pattern, group) -%}
    nullif(regexp_extract({{ expr }}, {{ mogov.regex_literal(pattern) }}, {{ group }}), '')
{%- endmacro %}

{% macro postgres__regex_extract(expr, pattern, group) -%}
    (regexp_match({{ expr }}, {{ mogov.regex_literal(pattern) }}))[{{ group }}]
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
    (regexp_instr({{ expr }}, {{ mogov.regex_literal(pattern) }}) > 0)
{%- endmacro %}

{% macro snowflake__regex_matches(expr, pattern) -%}
    (regexp_instr({{ expr }}, {{ mogov.regex_literal(pattern) }}) > 0)
{%- endmacro %}

{% macro duckdb__regex_matches(expr, pattern) -%}
    regexp_matches({{ expr }}, {{ mogov.regex_literal(pattern) }})
{%- endmacro %}

{% macro postgres__regex_matches(expr, pattern) -%}
    ({{ expr }} ~ {{ mogov.regex_literal(pattern) }})
{%- endmacro %}


{# Replace every match of pattern. #}
{% macro regex_replace_all(expr, pattern, replacement) -%}
    {{ return(adapter.dispatch('regex_replace_all', 'mogov')(expr, pattern, replacement)) }}
{%- endmacro %}

{% macro default__regex_replace_all(expr, pattern, replacement) -%}
    regexp_replace({{ expr }}, {{ mogov.regex_literal(pattern) }}, {{ mogov.regex_literal(replacement) }})
{%- endmacro %}

{% macro snowflake__regex_replace_all(expr, pattern, replacement) -%}
    regexp_replace({{ expr }}, {{ mogov.regex_literal(pattern) }}, {{ mogov.regex_literal(replacement) }})
{%- endmacro %}

{% macro duckdb__regex_replace_all(expr, pattern, replacement) -%}
    regexp_replace({{ expr }}, {{ mogov.regex_literal(pattern) }}, {{ mogov.regex_literal(replacement) }}, 'g')
{%- endmacro %}

{% macro postgres__regex_replace_all(expr, pattern, replacement) -%}
    regexp_replace({{ expr }}, {{ mogov.regex_literal(pattern) }}, {{ mogov.regex_literal(replacement) }}, 'g')
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


{# Normalize a person/org name for matching: lower-case, any character outside a-z/0-9/space (punctuation, accented letters) becomes a
   space, runs of spaces collapsed to one ("O'Hearn" -> "o hearn"; spaces are kept, not removed: "Health PAC" and "HealthPAC" differ, #108; callers split on them). #}
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

{# The character with code point `n` (e.g. 10 for a newline). BigQuery has no CHR; everything else here does. #}
{% macro chr(n) -%}
    {{ return(adapter.dispatch('chr', 'mogov')(n)) }}
{%- endmacro %}

{% macro default__chr(n) -%}
    chr({{ n }})
{%- endmacro %}

{% macro bigquery__chr(n) -%}
    code_points_to_string([{{ n }}])
{%- endmacro %}


{#
  The Nth part of a delimited string, N a column or expression. dbt.split_part needs a literal part number on
  some backends (BigQuery's SPLIT(...)[SAFE_OFFSET(n)]), so a CASE picks among literal-index calls: parts past
  max_parts are NULL. `delim` is a SQL literal, e.g. "', '".
#}
{% macro split_part_at(expr, delim, n, max_parts) -%}
    case {{ n }}
        {%- for i in range(1, max_parts + 1) %}
        when {{ i }} then {{ dbt.split_part(expr, delim, i) }}
        {%- endfor %}
    end
{%- endmacro %}


{# Levenshtein edit distance between two strings (null if either is null). DuckDB and Postgres (fuzzystrmatch) call it
   levenshtein, Snowflake editdistance. #}
{% macro edit_distance(a, b) -%}
    {{ return(adapter.dispatch('edit_distance', 'mogov')(a, b)) }}
{%- endmacro %}

{% macro default__edit_distance(a, b) -%}
    levenshtein({{ a }}, {{ b }})
{%- endmacro %}

{% macro snowflake__edit_distance(a, b) -%}
    editdistance({{ a }}, {{ b }})
{%- endmacro %}
