{#-
    The awards_threshold var (dbt_project.yml) as a checked dict: `default` plus optional per-award cutoffs.
    A misspelled award name or a non-integer cutoff would otherwise be ignored silently or render broken SQL,
    so either one stops the build with a compiler error.
-#}
{% macro awards_thresholds() %}
    {% set known_awards = [
        'lowest_attendance',
        'highest_attendance',
        'most_committee_money',
        'least_committee_money_share',
        'most_party_breaks',
        'most_party_loyal',
        'most_bills_passed_house',
    ] %}
    {% set cutoffs = var('awards_threshold') %}
    {% if 'default' not in cutoffs %}
        {{ exceptions.raise_compiler_error("awards_threshold needs a 'default' key") }}
    {% endif %}
    {% for award_name, cutoff in cutoffs.items() %}
        {% if award_name != 'default' and award_name not in known_awards %}
            {{ exceptions.raise_compiler_error(
                "awards_threshold has unknown award '" ~ award_name ~ "'; known awards: " ~ known_awards | join(', ')
            ) }}
        {% endif %}
        {% if cutoff is not integer or cutoff is boolean or cutoff < 0 %}
            {{ exceptions.raise_compiler_error(
                "awards_threshold '" ~ award_name ~ "' must be a whole number of at least 0 (0 leaves the award empty), got " ~ cutoff
            ) }}
        {% endif %}
    {% endfor %}
    {{ return(cutoffs) }}
{% endmacro %}
