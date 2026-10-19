{#- One spelling per party, whatever the source wrote: the MO House XML and congress-legislators say
    "Democrat", Open States "Democratic", some feeds use single letters. Unknown values pass through trimmed. -#}
{% macro normalize_party(expr) -%}
    case lower(trim({{ expr }}))
        when 'democrat' then 'Democratic'
        when 'democratic' then 'Democratic'
        when 'd' then 'Democratic'
        when 'republican' then 'Republican'
        when 'r' then 'Republican'
        when 'independent' then 'Independent'
        when 'i' then 'Independent'
        when 'libertarian' then 'Libertarian'
        when 'l' then 'Libertarian'
        else nullif(trim({{ expr }}), '')
    end
{%- endmacro %}
