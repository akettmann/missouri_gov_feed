{#- Fold the sources' counterparty / contributor types into the donor classes the reporting models share:
    individual, pac, party, candidate committee, committee, business or organization, other. MEC types:
    Individual / Committee / Organization / Corporation; FEC types come from the fec_committee_types seed. -#}
{% macro donor_class(expr) -%}
    case
        when lower({{ expr }}) = 'individual' then 'individual'
        when lower({{ expr }}) like '%pac%' then 'pac'
        when lower({{ expr }}) like 'party%' then 'party'
        when {{ expr }} in ('House', 'Senate', 'Presidential') then 'candidate committee'
        when lower({{ expr }}) = 'committee' then 'committee'
        when lower({{ expr }}) in ('corporation', 'organization') then 'business or organization'
        else 'other'
    end
{%- endmacro %}
