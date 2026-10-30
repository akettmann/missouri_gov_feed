{#
  Canonical key of a statewide executive office from the title a source uses, so the same office reads the same
  across sources: "Governor" (statewide_officials seed), "Governor of Missouri" (Wikidata), "Lt Governor" (Open States),
  "Missouri State Treasurer" (Wikidata). Any other title (a legislative seat, a judgeship) comes back lower-cased and
  otherwise unchanged, so it never merges with a statewide office (#760).
#}
{% macro statewide_office_key(title_expr) -%}
    case
        when {{ mogov.statewide_office_stripped(title_expr) }} in ('lt governor', 'lt. governor', 'lieutenant governor')
            then 'lieutenant governor'
        when {{ mogov.statewide_office_stripped(title_expr) }} in (
            'governor', 'secretary of state', 'state auditor', 'state treasurer', 'attorney general'
        )
            then {{ mogov.statewide_office_stripped(title_expr) }}
        else lower({{ title_expr }})
    end
{%- endmacro %}

{# lower-cased title without "Missouri" ("Governor of Missouri", "Missouri State Treasurer"). #}
{% macro statewide_office_stripped(title_expr) -%}
    trim(replace(replace(lower({{ title_expr }}), ' of missouri', ''), 'missouri ', ''))
{%- endmacro %}

{# True when the key from statewide_office_key names one of the six statewide executive offices. #}
{% macro is_statewide_office_key(key_expr) -%}
    {{ key_expr }} in (
        'governor', 'lieutenant governor', 'secretary of state', 'state auditor', 'state treasurer', 'attorney general'
    )
{%- endmacro %}
