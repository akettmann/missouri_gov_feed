{#
  Committee names, normalized for matching a donor committee's name (as another committee reported it) to a
  filing committee's own name. Built on the portable string macros in compat/strings.sql.

  Tokens are matched whole: every space of the name_key is doubled and the key padded with a space, so a
  pattern like ' mo ' matches each token without two matches competing for the space between them.
#}
{% macro _spaced(key) -%}
    ' ' || {{ dbt.replace(key, "' '", "'  '") }} || ' '
{%- endmacro %}

{% macro _squeeze(expr) -%}
    trim({{ mogov.regex_replace_all(expr, ' +', ' ') }})
{%- endmacro %}


{# committee_key: name_key with filers' abbreviations spelled out (MO, KC, STL, Assn, Cmte, Natl, Intl, Pol,
   Govt, Dist), "Saint" shortened to "St", "Local No. 513" to "Local 513", and connective / legal-form words
   dropped, so "MO Independent Bankers Assoc PAC" and "Missouri Independent Bankers Association PAC" give the
   same key. Replacements keep doubled spaces so later rules still see whole tokens. #}
{% macro committee_key(expr) -%}
    {%- set rules = [
        (' ass  n ', ' association '),
        (' nat  l ', ' national '),
        (' int  l ', ' international '),
        (' local  (no|number) ', ' local '),
        (' mo ', ' missouri '),
        (' kc ', ' kansas  city '),
        (' stl ', ' st  louis '),
        (' saint ', ' st '),
        (' (assn|assoc|asso|ass|associations) ', ' association '),
        (' (cmte|cmtee|cmt|comm|committe|commitee) ', ' committee '),
        (' natl ', ' national '),
        (' (intl|int) ', ' international '),
        (' (pol|polit) ', ' political '),
        (' govt ', ' government '),
        (' dist ', ' district '),
        (' (the|of|for|and|a|an|in|inc|incorporated|llc|corp) ', ' '),
    ] -%}
    {%- set ns = namespace(sql=mogov._spaced(mogov.name_key(expr))) -%}
    {%- for pattern, replacement in rules -%}
        {%- set ns.sql = mogov.regex_replace_all(ns.sql, pattern, replacement) -%}
    {%- endfor -%}
    {{ mogov._squeeze(ns.sql) }}
{%- endmacro %}


{# committee_core_key: committee_key without the words that only say it's a committee (PAC, P A C, Political,
   Action, Committee, Fund, Account), so "Quality Building PAC" and "Quality Building Political Action
   Committee" match. Coarse on purpose: callers must require a unique result and a minimum length. #}
{% macro committee_core_key(expr) -%}
    {%- set spaced = mogov._spaced(mogov.committee_key(expr)) -%}
    {%- set no_pac = mogov.regex_replace_all(spaced, ' p  a  c ', ' ') -%}
    {{ mogov._squeeze(mogov.regex_replace_all(no_pac, ' (pac|political|action|committee|fund|account) ', ' ')) }}
{%- endmacro %}


{# The name outside any parentheses, and the first parenthesized part: "Carpenters Help in the Political
   Process (CHIPP)" -> "Carpenters Help in the Political Process" and "CHIPP". #}
{% macro outside_parens(expr) -%}
    {{ mogov.regex_replace_all(expr, '[(][^)]*[)]', ' ') }}
{%- endmacro %}

{% macro inside_parens(expr) -%}
    {{ mogov.regex_extract(expr, '[(]([^)]*)[)]') }}
{%- endmacro %}
