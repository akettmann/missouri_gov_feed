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

{#- One part of a filer's first / last name that counts as a person's name (#485): trimmed, or null for the filler MEC
    filers type where a name doesn't apply: one-character values ('x'), 'PAC', 'N/A' / '#N/A', 'Not applicable',
    'None', and anything with no letter or number or all digits. (A real initial is a name_part, but alone it
    is not enough to call the donor a person.) -#}
{% macro real_name_part(expr) -%}
    case
        when
            length(trim({{ expr }})) >= 2
            and {{ mogov.regex_matches(expr, '[A-Za-z0-9]') }}
            and not {{ mogov.regex_matches('trim(' ~ expr ~ ')', '^[0-9]+$') }}
            and lower(trim({{ expr }})) not in ('pac', 'n/a', '#n/a', 'na', 'none', 'not applicable')
            then trim({{ expr }})
    end
{%- endmacro %}

{#- A filer's last name as a person's surname (#485): real_name_part, but null when it holds a digit. A digit means a
    street address typed into the last-name column ("700 12th Avenue South") of a shifted row, not a surname. -#}
{% macro real_last_part(expr) -%}
    case
        when not coalesce({{ mogov.regex_matches(expr, '[0-9]') }}, false) then {{ mogov.real_name_part(expr) }}
    end
{%- endmacro %}

{#- Whether a filer's first / last name columns hold a person's name: at least one part is not a filler (and the last
    name is not an address). -#}
{% macro has_person_name(first_expr, last_expr) -%}
    coalesce(
        {{ mogov.real_name_part(first_expr) }} is not null or {{ mogov.real_last_part(last_expr) }} is not null, false
    )
{%- endmacro %}

{#- name_key without middle initials (any single-letter word) and generational suffixes (jr, sr, ii, iii, iv), so
    "Rex A. Sinquefield" equals "Rex Sinquefield" and "Jones Jr" equals "Jones" (#485). Two passes, because
    adjacent words share their separating space. -#}
{% macro person_key(expr) -%}
    trim({{ mogov.regex_replace_all(
        mogov.regex_replace_all(
            mogov.regex_replace_all(
                "' ' || " ~ mogov.name_key(expr) ~ " || ' '", ' ([a-z]|jr|sr|ii|iii|iv) ', ' '
            ),
            ' ([a-z]|jr|sr|ii|iii|iv) ', ' '
        ),
        ' +', ' '
    ) }})
{%- endmacro %}

{#- The company column as a company name: trimmed, or null for a filler (blank, 'N/A', 'NONE', 'Individual', all
    digits, one character). -#}
{% macro real_company(expr) -%}
    case
        when
            {{ mogov.clean_name(expr) }} is not null
            and upper(trim({{ expr }})) not in ('NONE', 'N/A', 'NA', '#N/A', 'NOT APPLICABLE', 'INDIVIDUAL')
            and not {{ mogov.regex_matches('trim(' ~ expr ~ ')', '^[0-9]+$') }}
            then trim({{ expr }})
    end
{%- endmacro %}

{#- Whether the company is not a business but the person (#485): the person's own name ("Natalie DiNicola",
    "DiNicola, Natalie", "Rex A. Sinquefield" beside Rex / Sinquefield; middle initials and suffixes ignored), a bare
    given name or surname (a shifted row: surname in first_name, given name in company, or the first name repeated),
    or the recipient committee's own name. Needs a person's name to be true: a filler name leaves nothing to repeat, so
    the company is the donor. A name whose first and last parts are equal (an organization typed into both fields,
    "ANC Properties" / "ANC Properties") is no person's name, and a multi-word company that equals only the first or
    only the last part ("Vantage CU" as first_name and company) is that organization, not a person. -#}
{% macro company_is_person_name(company_expr, first_expr, last_expr, recipient_expr) -%}
    coalesce(
        {{ mogov.has_person_name(first_expr, last_expr) }}
        and {{ mogov.real_company(company_expr) }} is not null
        and (
            {{ mogov.name_key(company_expr) }} = {{ mogov.name_key(recipient_expr) }}
            or (
                -- both name parts present and different: the company is the whole name, either way round
                {{ mogov.real_name_part(first_expr) }} is not null
                and {{ mogov.real_last_part(last_expr) }} is not null
                and {{ mogov.name_key(first_expr) }} <> {{ mogov.name_key(last_expr) }}
                and {{ mogov.person_key(company_expr) }} <> ''
                and {{ mogov.person_key(company_expr) }} in (
                    {{ mogov.person_key("coalesce(" ~ first_expr ~ ", '') || ' ' || coalesce(" ~ last_expr ~ ", '')") }},
                    {{ mogov.person_key("coalesce(" ~ last_expr ~ ", '') || ' ' || coalesce(" ~ first_expr ~ ", '')") }}
                )
            )
            or (
                -- a single-word company is a bare given name or surname of a shifted row: the half of the name that is
                -- missing
                {{ mogov.name_key(company_expr) }} not like '% %'
                and (
                    {{ mogov.real_name_part(first_expr) }} is null
                    or {{ mogov.real_last_part(last_expr) }} is null
                )
            )
            or (
                -- a company that repeats one of two different halves of the name: a multi-word given name ("Ellen Y"
                -- as first_name and company). With the other half missing it is an organization ("Vantage CU").
                {{ mogov.real_name_part(first_expr) }} is not null
                and {{ mogov.real_last_part(last_expr) }} is not null
                and {{ mogov.name_key(first_expr) }} <> {{ mogov.name_key(last_expr) }}
                and (
                    {{ mogov.name_key(company_expr) }} in ({{ mogov.name_key(first_expr) }}, {{ mogov.name_key(last_expr) }})
                    -- or one whole word of a multi-word given name ("Christopher Busken" as first_name, "Christopher"
                    -- as company)
                    or ' ' || {{ mogov.name_key(first_expr) }} || ' ' like '% ' || {{ mogov.name_key(company_expr) }} || ' %'
                )
            )
        ),
        false
    )
{%- endmacro %}

{#- The name of a donor whose last-name column holds a street address (a shifted row, #485): the given or family name
    that is left, without the address. Null when there is a name in the last column or no company. -#}
{% macro first_name_beside_address(company_expr, first_expr, last_expr) -%}
    case
        when
            {{ mogov.real_company(company_expr) }} is not null
            and coalesce({{ mogov.regex_matches(last_expr, '[0-9]') }}, false)
            then {{ mogov.name_part(first_expr) }}
    end
{%- endmacro %}

{#- The company as the donor: the business named in `company`, when there is one. MEC's convention (#485) is that a
    filled company is the donor and the first / last name is its contact person, so the donor is the company except
    when it only repeats the person (see company_is_person_name). Null when the company is not the donor. -#}
{% macro donor_company(company_expr, first_expr, last_expr, recipient_expr) -%}
    case
        when not {{ mogov.company_is_person_name(company_expr, first_expr, last_expr, recipient_expr) }}
            then {{ mogov.real_company(company_expr) }}
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
