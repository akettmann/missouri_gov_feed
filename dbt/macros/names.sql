{#- Helpers for names typed into free-text filer columns. Filers use fillers ('~', '-', '?', '.', 'C') where a field
    doesn't apply; these rules are the ones stg_tap_mec__contributions applies (#31, #53, #60). -#}

{#- A whole name (organization or full person name): trimmed, or null when it is shorter than 2 characters or has no
    letter or number. -#}
{% macro clean_name(expr) -%}
    case
        when length(trim({{ expr }})) >= 2 and {{ mogov.regex_matches(expr, '[A-Za-z0-9]') }} then trim({{ expr }})
    end
{%- endmacro %}

{#- One part of a person's name (first or last): trimmed, or null when it has no letter or number (real initials
    like 'R' stay) or is all digits (not a name; a numeric first_name marks a shifted-column row, see #60). -#}
{% macro name_part(expr) -%}
    case
        when
            {{ mogov.regex_matches(expr, '[A-Za-z0-9]') }} and not {{ mogov.regex_matches('trim(' ~ expr ~ ')', '^[0-9]+$') }}
            then trim({{ expr }})
    end
{%- endmacro %}

{#- "First Last" from whichever parts are usable; null when neither is. A numeric first_name means the row's
    columns are shifted (#60), so no name is built from it. -#}
{% macro person_name(first_expr, last_expr) -%}
    case
        when not coalesce({{ mogov.regex_matches('trim(' ~ first_expr ~ ')', '^[0-9]+$') }}, false)
            then nullif(
                trim(coalesce({{ mogov.name_part(first_expr) }}, '') || ' ' || coalesce({{ mogov.name_part(last_expr) }}, '')),
                ''
            )
    end
{%- endmacro %}
