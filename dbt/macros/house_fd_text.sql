{# House disclosure PDFs from 2021 on set every small-caps run in a font that text extraction turns into NUL
   characters: the first (capital) letter survives and each lowercase-size letter after it becomes one NUL, so
   "SCHEDULE" extracts as "S" + 7 NULs, "DESCRIPTION" as "D" + 10, "LOCATION" as "L" + 7, "COMMENTS" as "C" + 7 and "A and B" as
   "A" + " " + 3 NULs + " " + "B". The letter counts are preserved, so the words we key on are recoverable
   exactly. The raw text stays unchanged in raw storage and staging; this repairs the words the schedule parser
   matches on (#576) and drops the NULs that remain (labels we do not match on) so that no NUL reaches the
   marts. Restores are anchored to the start of the line and to the exact NUL count, so another label that
   merely starts with S ("S" + 9 NULs + " O" + 1 NUL, the owner label on asset detail lines) is not mistaken
   for a schedule header. #}
{% macro house_fd_restore_text(expr) -%}
    {#- Built by concatenation: dbt's Jinja decodes a backslash-x00 string literal into a real NUL character. -#}
    {%- set bs = '\\' -%}
    {%- set nul = bs ~ 'x00' -%}
    {%- set restores = [
        ['^S' ~ nul ~ '{7}( [A-J])', 'Schedule' ~ bs ~ '1'],
        ['^(Schedule [A-J]) ' ~ nul ~ '{3} B', bs ~ '1 and B'],
        ['^D' ~ nul ~ '{10}:', 'Description:'],
        ['^L' ~ nul ~ '{7}:', 'Location:'],
        ['^C' ~ nul ~ '{7}:', 'Comments:'],
        ['^C' ~ nul ~ '{12} ' ~ nul ~ '{3} S' ~ nul ~ '{8}$', 'Certification and Signature'],
        [
            '^E' ~ nul ~ '{9} ' ~ nul ~ '{2} S' ~ nul ~ '{5}, D' ~ nul ~ '{8}, ' ~ nul ~ '{2} T' ~ nul ~ '{4} I' ~ nul ~ '{10}$',
            'Exclusions of spouse, dependent, or trust information',
        ],
        ['^(Schedule A( and B)?) A' ~ nul ~ '{4} C' ~ nul ~ '{4} D' ~ nul ~ '{6}$', bs ~ '1 Asset Class Details'],
        ['^(Schedule A( and B)?) I' ~ nul ~ '{9} V' ~ nul ~ '{6} D' ~ nul ~ '{6}$', bs ~ '1 Investment Vehicle Details'],
        ['^S' ~ nul ~ '{9} O' ~ nul ~ ':', 'Subholding Of:'],
        ['^F' ~ nul ~ '{5} S' ~ nul ~ '{5}:', 'Filing Status:'],
        [nul ~ '+', ''],
    ] -%}
    {%- set ns = namespace(sql=expr) -%}
    {%- for r in restores -%}
        {%- set ns.sql = mogov.regex_replace_all(ns.sql, r[0], r[1]) -%}
    {%- endfor -%}
    {{ ns.sql }}
{%- endmacro %}
