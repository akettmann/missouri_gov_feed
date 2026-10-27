{#- Shared BILLSTATUS expressions, so the staging models that must agree on a key or a normalized label do. -#}

{#- Lower case, hyphens as spaces, runs of spaces and hyphens collapsed to one space, trimmed:
    "Bills of Interest - Exchange of Letters" -> "bills of interest exchange of letters". -#}
{% macro billstatus_label_normalized(expr) -%}
    lower(trim({{ mogov.regex_replace_all(expr, '[- ]+', ' ') }}))
{%- endmacro %}

{#- A related bill's id in the form of bill_id ("118-hjres-125"): congress and number as integers, type lower case.
    Pass the raw json values; the same expression builds related_bill_id and finds a bill related to itself. -#}
{% macro billstatus_related_bill_id(congress, bill_type, number) -%}
    {{ dbt.safe_cast(dbt.safe_cast(congress, dbt.type_int()), dbt.type_string()) }}
    || '-' || lower({{ bill_type }}) || '-'
    || {{ dbt.safe_cast(dbt.safe_cast(number, dbt.type_int()), dbt.type_string()) }}
{%- endmacro %}
