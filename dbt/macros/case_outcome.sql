{#- Classify a court's disposition text (or the closing text of an opinion) into a fixed vocabulary:
      writ granted | writ denied | transferred | affirmed in part, reversed in part |
      reversed and remanded | vacated | reversed | affirmed | dismissed | remanded | other
    Rules run in that order because wordings overlap: "affirmed and remanded" is an affirmance, "appeal
    dismissed; cause remanded" a dismissal, "affirmed as to points I-IV, reversed as to point V" mixed.
    Null in, null out; text that matches nothing is 'other'. Portable: upper() + like only. -#}
{% macro classify_outcome(expr) -%}
    {%- set t = 'upper(' ~ expr ~ ')' -%}
    {#- Missouri also words writs as "preliminary order in mandamus / of prohibition made permanent" -#}
    {%- set writ = '(' ~ t ~ " like '%WRIT%' or " ~ t ~ " like '%MANDAMUS%' or " ~ t ~ " like '%PROHIBITION%')" -%}
    case
        when {{ expr }} is null or trim({{ expr }}) = '' then null
        when {{ writ }} and (
            {{ t }} like '%PERMANENT%' or {{ t }} like '%ABSOLUTE%'
            or {{ t }} like '%ISSUED%' or {{ t }} like '%GRANTED%'
        ) then 'writ granted'
        when {{ writ }} and ({{ t }} like '%QUASH%' or {{ t }} like '%DENIED%') then 'writ denied'
        when {{ t }} like '%TRANSFER%' then 'transferred'
        when {{ t }} like '%IN PART%' or ({{ t }} like '%AFFIRM%' and ({{ t }} like '%REVERS%' or {{ t }} like '%VACAT%'))
            then 'affirmed in part, reversed in part'
        when {{ t }} like '%REVERS%' and {{ t }} like '%REMAND%' then 'reversed and remanded'
        when {{ t }} like '%VACAT%' then 'vacated'
        when {{ t }} like '%REVERS%' then 'reversed'
        when {{ t }} like '%AFFIRM%' then 'affirmed'
        when {{ t }} like '%DISMISS%' then 'dismissed'
        when {{ t }} like '%REMAND%' then 'remanded'
        else 'other'
    end
{%- endmacro %}
