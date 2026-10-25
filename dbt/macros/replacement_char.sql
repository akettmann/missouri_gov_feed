{# Text with the U+FFFD replacement character repaired. EPA's own FRS state file already contains U+FFFD where
   its pipeline lost a non-ASCII character (the raw zip has the bytes EF BF BD; our loader decodes strictly, so
   nothing is introduced here). The lost letter is not recoverable from the text itself, and EPA's other records
   for the same sites spell the words without an accent ("DECOR PLUS", "MARBLE DECOR INC"). So the known cases
   come from the epa_frs_name_corrections seed (each row cites the EPA record that attests the value), passed as
   `correction` (a column that is null when there is none) and used only while the text still contains U+FFFD.
   Any other U+FFFD is dropped, with no word-specific guessing. #}
{% macro fix_replacement_char(expr, correction='null') -%}
    case
        when {{ expr }} like '%�%' and {{ correction }} is not null then {{ correction }}
        else {{ mogov.regex_replace_all(expr, '�+', '') }}
    end
{%- endmacro %}
