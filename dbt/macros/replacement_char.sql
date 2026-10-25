{# Text with the U+FFFD replacement character repaired. EPA's own FRS state file already contains U+FFFD where
   its pipeline lost a non-ASCII character (the raw zip has the bytes EF BF BD; our loader decodes strictly, so
   nothing is introduced here). The lost letter is not recoverable from the text itself, and EPA's other records
   for the same sites spell the words without an accent ("DECOR PLUS", "MARBLE DECOR INC"). So the known cases
   come from `correction` (a column that is null when there is none), used only while the text still contains
   U+FFFD: staging passes the epa_frs_name_corrections seed's value if it has one (a maintainer override), else
   the matching alternative name (see damaged_name_pattern). Any other U+FFFD is dropped, with no word-specific
   guessing. #}
{% macro fix_replacement_char(expr, correction='null') -%}
    case
        when {{ expr }} like '%�%' and {{ correction }} is not null then {{ correction }}
        else {{ mogov.regex_replace_all(expr, '�+', '') }}
    end
{%- endmacro %}


{# LIKE pattern (use with ESCAPE '!') for the names a damaged name could have been: each run of U+FFFD stands for
   exactly one lost character (a two-byte letter shows as one or two U+FFFD), so it becomes `_`; every other
   character must match as is, with LIKE's own wildcards escaped by `!`. "D�COR PLUS" -> "D_COR PLUS", which
   "DECOR PLUS" matches and "DECORATING PLUS" does not. The damaged name is trimmed first (alternative names are
   trimmed in staging). ESCAPE is not portable: BigQuery has no LIKE ... ESCAPE (it escapes with backslash in the
   pattern), so a BigQuery backend needs its own variant of this macro and of the `escape '!'` in staging. #}
{% macro damaged_name_pattern(expr) -%}
    {{ mogov.regex_replace_all("replace(replace(replace(trim(" ~ expr ~ "), '!', '!!'), '%', '!%'), '_', '!_')", '�+', '_') }}
{%- endmacro %}
