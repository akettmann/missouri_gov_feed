{#-
    The paired top/bottom awards of rpt_awards: each pair is two ends of one comparison (same order as
    frontend/src/lib/exports/awardDefs.ts AWARD_PAIRS). An award in a pair takes at most half of its ranked
    field, and an official both lists would still share is dropped from both. An award in no pair is untouched.
-#}
{% macro awards_pairs() %}
    {{ return([
        ['lowest_attendance', 'highest_attendance'],
        ['most_committee_money', 'least_committee_money_share'],
        ['most_party_breaks', 'most_party_loyal'],
    ]) }}
{% endmacro %}

{#- SQL expression: the pair's name (first award of the pair) for an award column, null when it has no pair -#}
{% macro award_pair_expr(award_col) %}
    case
        {%- for pair in mogov.awards_pairs() %}
        when {{ award_col }} in ('{{ pair[0] }}', '{{ pair[1] }}') then '{{ pair[0] }}'
        {%- endfor %}
    end
{%- endmacro %}
