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

{#- A payroll surname as a match key: name_key without the trailing generational or professional suffixes the payroll
    prints inside the surname field ("BRATTIN JR.", "HADEN DVM"), so it equals the official's family name. -#}
{% macro surname_key(expr) -%}
    {{ mogov.regex_replace_all(mogov.name_key(expr), '( (jr|sr|ii|iii|iv|md|dvm|dds|dmd|phd|esq|cpa))+$', '') }}
{%- endmacro %}

{#- How well a payroll first name fits an official's given name, for people already known to share a surname:
    3 the first names are equal; 2 the given name is one of the payee's names ("JOHN KENT" for Kent); 1 one starts
    with the other or they share their first three letters (Ed/Edwin, Patty/Patricia); 0 no fit. Equal initials
    fit; an initial never fits a different name. -#}
{% macro first_name_fit(first_key, first_all_key, given_key) -%}
    case
        when {{ first_key }} = {{ given_key }} then 3
        when length({{ first_key }}) < 2 or length({{ given_key }}) < 2 then 0
        when ' ' || {{ first_all_key }} || ' ' like '% ' || {{ given_key }} || ' %' then 2
        when
            left({{ first_key }}, 3) = left({{ given_key }}, 3)
            or {{ first_key }} like {{ given_key }} || '%'
            or {{ given_key }} like {{ first_key }} || '%'
            then 1
        else 0
    end
{%- endmacro %}
