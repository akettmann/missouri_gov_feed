{#- Human-readable dataset page for a Socrata API URL: https://data.mo.gov/resource/<id>.json (or .csv, .geojson, with
    or without a query string) becomes https://data.mo.gov/d/<id>, which redirects to the dataset's landing page (the
    API URL opens a raw JSON dump). Only a URL of the form <scheme>://<host>/resource/<4x4 id> followed by an
    extension, query string, fragment or nothing is rewritten: the host is kept, everything after the id is dropped.
    Anything else (an existing /d/ page, a non-Socrata URL that happens to contain /resource/, NULL) passes through
    unchanged. -#}
{% macro socrata_page_url(expr) -%}
    {%- set api_pattern = '^https?://[^/?#]+/resource/[a-z0-9]{4}-[a-z0-9]{4}([.?#/]|$)' -%}
    case
        when {{ mogov.regex_matches(expr, api_pattern) }}
            then {{ dbt.concat([
                mogov.regex_extract(expr, '^(https?://[^/?#]+)/resource/', 1),
                "'/d/'",
                mogov.regex_extract(expr, '^https?://[^/?#]+/resource/([a-z0-9]{4}-[a-z0-9]{4})', 1),
            ]) }}
        else {{ expr }}
    end
{%- endmacro %}
