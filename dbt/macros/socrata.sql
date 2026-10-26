{#- Human-readable dataset page for a Socrata API URL: https://data.mo.gov/resource/<id>.json (or .csv) becomes
    https://data.mo.gov/d/<id>, which redirects to the dataset's landing page (the API URL opens a raw JSON dump).
    Anything that is not a /resource/ URL passes through unchanged. -#}
{% macro socrata_page_url(expr) -%}
    case
        when {{ expr }} like '%/resource/%'
            then {{ dbt.replace(dbt.replace(dbt.replace(expr, "'/resource/'", "'/d/'"), "'.json'", "''"), "'.csv'", "''") }}
        else {{ expr }}
    end
{%- endmacro %}
