{#-
    The paired top/bottom awards of rpt_awards: each pair is two ends of one ranking (same order as
    frontend/src/lib/exports/awardDefs.ts AWARD_PAIRS, which only sets display order). Both awards of a pair must
    rank the same number over the same field (same group_size per office and period; the singular test
    assert_award_pairs_same_field checks it), so a pair is never a dollar award with a share award. An award in a pair takes at most half of its ranked
    field, and an official both lists would still share is dropped from both. An award in no pair is untouched.
-#}
{% macro awards_pairs() %}
    {{ return([
        ['lowest_attendance', 'highest_attendance'],
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
