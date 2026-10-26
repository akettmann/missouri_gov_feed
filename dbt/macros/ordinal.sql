{#- English ordinal suffix for a whole number: 1st, 2nd, 3rd, 4th ... 11th, 12th, 13th, 21st, 111th, 121st.
    Teens (11-13 and 111-113 ...) are always "th". Uses only case and mod(), which every backend has. -#}
{% macro ordinal(expr) -%}
    {{ dbt.safe_cast(expr, dbt.type_string()) }}
    || case
        when mod({{ expr }}, 100) between 11 and 13 then 'th'
        when mod({{ expr }}, 10) = 1 then 'st'
        when mod({{ expr }}, 10) = 2 then 'nd'
        when mod({{ expr }}, 10) = 3 then 'rd'
        else 'th'
    end
{%- endmacro %}
