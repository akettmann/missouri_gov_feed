{# Text with the U+FFFD replacement character repaired. EPA's own FRS state file already contains U+FFFD where
   its pipeline lost a non-ASCII character (the raw zip has the bytes EF BF BD; our loader decodes strictly, so
   nothing is introduced here). "D<FFFD>COR" is restored to "DÉCOR", the only case where the lost letter is
   certain (two FFFD in a row, as in "MARBLE D<FFFD><FFFD>COR INC", is the same letter in two bytes). Any other
   U+FFFD is dropped: the intended character cannot be recovered. #}
{% macro fix_replacement_char(expr) -%}
    {{ mogov.regex_replace_all(
        mogov.regex_replace_all(expr, 'D�+COR', 'DÉCOR'), '�+', ''
    ) }}
{%- endmacro %}
