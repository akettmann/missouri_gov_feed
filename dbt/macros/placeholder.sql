{#- Null for the filler values filers type when a field doesn't apply ("NONE", "N/A"), else the value. The FEC
    committee master writes "NONE" for no connected organization; MEC filers write it as an employer. -#}
{% macro null_if_placeholder(expr) -%}
    case when upper(trim({{ expr }})) not in ('', 'NONE', 'N/A', 'NA') then {{ expr }} end
{%- endmacro %}
