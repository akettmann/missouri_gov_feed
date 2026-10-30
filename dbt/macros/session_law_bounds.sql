{# Parse bounds for the Revisor's session-law citations (int_mo_revisor__session_law_bills). split_part_at takes a
   literal maximum number of parts and silently drops the rest, so each bound must exceed what real data needs;
   tests/assert_session_law_bounds_not_exceeded.sql fails the build when it doesn't. Longest real values (Oct 2026):
   43 acts in one note (RSMo 301.010), 6 bills "merged with" in one act, 4 bills joined by "&" or "and" in one act. #}
{% macro session_law_bounds() -%}
    {{ return({'max_acts': 60, 'max_merged': 10, 'max_combined': 6}) }}
{%- endmacro %}

{# The history or repeal note with one separator (", ") between acts and "et al." attached to the act before it. A
   trailing act joined with "and" ("H.B. 1489 and A.L. 2004 S.B. 1233 et al.") is an act of its own, so it gets the
   same separator. " and Repealed L." starts a repealed act of its own. " and L." gets a leading "@" on the act: the
   Revisor's "L." is the act that made the text, "A.L." one that amended it, and "Repealed" governs the whole list in
   a repeal note, so a bare "L." that follows a repealed act ("Repealed L. 2013 H.B. 374 & 434 and L. 2016 S.B. 585")
   is one more repealing act, not an enactment (int_mo_revisor__session_law_bills reads and strips the marker). #}
{% macro normalize_session_law_note(expr) -%}
    replace(
        replace(
            replace(
                replace(replace(replace(replace({{ expr }}, '(', ''), ')', ''), '; ', ', '), ' and A.L. ', ', A.L. '),
                ' and Repealed L. ',
                ', Repealed L. '
            ),
            ' and L. ', ', @L. '
        ),
        ', et al.', ' et al.'
    )
{%- endmacro %}
