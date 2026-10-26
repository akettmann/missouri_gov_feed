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

{#- Whether a filer's first / last name columns hold a person's name (#485). MEC exports a company beside the person's
    name for people who list an employer ("Natalie" / "DiNicola" / company "Natalie", or a credit union's staff with
    the credit union as company), so a company alone does not make the donor an organization. Not a person: both
    parts blank, or both a "no value" filler ('#N/A', 'Not applicable'), where the company is the real donor. -#}
{% macro has_person_name(first_expr, last_expr) -%}
    coalesce(
        (nullif(trim({{ first_expr }}), '') is not null or nullif(trim({{ last_expr }}), '') is not null)
        and not (
            lower(trim(coalesce({{ first_expr }}, ''))) in ('#n/a', 'n/a', 'not applicable', 'none')
            and lower(trim(coalesce({{ last_expr }}, ''))) in ('#n/a', 'n/a', 'not applicable', 'none')
        ),
        false
    )
{%- endmacro %}

{#- The company column unless it is part of the person's own name (#485): MEC filers often type the donor's name into
    `company` as well, and that is not an employer. That is the first name, last name or both repeated, or, when
    only one of first / last name is filled (a shifted row: surname in first_name, given name in company), the other
    half of the name. -#}
{% macro company_unless_person_name(company_expr, first_expr, last_expr) -%}
    case
        when
            lower(trim({{ company_expr }})) in (
                lower(trim({{ first_expr }})),
                lower(trim({{ last_expr }})),
                lower(trim(coalesce({{ first_expr }}, '') || ' ' || coalesce({{ last_expr }}, '')))
            )
            or (
                (
                    (nullif(trim({{ first_expr }}), '') is null and nullif(trim({{ last_expr }}), '') is not null)
                    or (nullif(trim({{ first_expr }}), '') is not null and nullif(trim({{ last_expr }}), '') is null)
                )
                and {{ mogov.has_person_name(first_expr, last_expr) }}
            )
            then null
        else {{ company_expr }}
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

{#- Free text from a registry (EPA FRS names, street addresses, cities) as shown to a reader: runs of whitespace
    (tabs included) become one space, and any run of commas, each with an optional space before it, becomes one comma
    ("LIPPERT FAMILY FARM,, LLC" is "LIPPERT FAMILY FARM, LLC", "NEMO FEEDS , LLC" is "NEMO FEEDS, LLC", "T 33N ,R 04W"
    is "T 33N,R 04W", "A , , B" is "A, B"; #399). Commas, semicolons and whitespace are cut from both ends, so
    "BUTTERBALL," and "900 WATSON DR,  " lose their stray comma while "ACME INC." and "SUITE 1" keep their own
    punctuation. Doubled semicolons are left alone: "K-BAR-L ;;C" is probably a shifted-hand typo for "LLC", not a
    separator. Null when nothing is left. HTML entities are decoded first (decode_registry_entities, #398). The ends
    are cut in one pass: the leading and the trailing run are separate patterns, so each is a plain anchored match. #}
{% macro clean_registry_text(expr) -%}
    nullif(
        {{ mogov.regex_replace_all(
            mogov.regex_replace_all(
                mogov.regex_replace_all(
                    mogov.regex_replace_all(mogov.decode_registry_entities(expr), '[[:space:]]+', ' '),
                    '( ?,)+', ','
                ),
                '^[,;[:space:]]+', ''
            ),
            '[,;[:space:]]+$', ''
        ) }},
        ''
    )
{%- endmacro %}


{#- The HTML entities EPA FRS writes into its text (#398), decoded: &AMP; / &amp; to '&' and the numeric &#39; &#40;
    &#41; to ' ( ). Only the entities that occur in the files are decoded, so a bare '&' ("AT&T") and any other
    text are left alone. '&' is decoded last, so a double-encoded "&amp;#39;" ends as "&#39;" and is not decoded
    twice (none occur). A new entity in a later EPA file shows up in the stg_epa_frs__* no-entity tests. -#}
{% macro decode_registry_entities(expr) -%}
    replace(
        replace(
            replace(
                replace(
                    replace({{ expr }}, '&#39;', ''''),
                    '&#40;', '('
                ),
                '&#41;', ')'
            ),
            '&AMP;', '&'
        ),
        '&amp;', '&'
    )
{%- endmacro %}
