{# Parse bounds for the Revisor's session-law citations (int_mo_revisor__session_law_bills). split_part_at takes a
   literal maximum number of parts and silently drops the rest, so each bound must exceed what real data needs;
   tests/assert_session_law_bounds_not_exceeded.sql fails the build when it doesn't. Longest real values (Oct 2026):
   43 acts in one note (RSMo 301.010), 6 bills "merged with" in one act, 4 bills joined by "&" or "and" in one act. #}
{% macro session_law_bounds() -%}
    {{ return({'max_acts': 60, 'max_merged': 10, 'max_combined': 6}) }}
{%- endmacro %}

{# The history or repeal note with one separator (", ") between acts and "et al." attached to the act before it. A
   trailing act joined with "and" ("H.B. 1489 and A.L. 2004 S.B. 1233 et al.") is an act of its own, so it gets the
   same separator. #}
{% macro normalize_session_law_note(expr) -%}
    replace(
        replace(
            replace(replace(replace(replace({{ expr }}, '(', ''), ')', ''), '; ', ', '), ' and A.L. ', ', A.L. '),
            ' and L. ', ', L. '
        ),
        ', et al.', ' et al.'
    )
{%- endmacro %}
