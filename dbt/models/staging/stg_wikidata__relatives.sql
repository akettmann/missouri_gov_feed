-- Officials' relatives on Wikidata, with any organization the relative leads and offices they hold.
{% set strip = "replace({}, 'http://www.wikidata.org/entity/', '')" %}
select
    {{ strip.format(mogov.json_str('payload', '$.person')) }} as qid,
    case replace({{ mogov.json_str('payload', '$.relation') }}, 'http://www.wikidata.org/prop/direct/', '')
        when 'P22' then 'father'
        when 'P25' then 'mother'
        when 'P26' then 'spouse'
        when 'P40' then 'child'
        when 'P3373' then 'sibling'
        when 'P1038' then 'relative'
        when 'P451' then 'partner'
    end as relation,
    {{ strip.format(mogov.json_str('payload', '$.relative')) }} as relative_qid,
    {{ mogov.json_str('payload', '$.relativeLabel') }} as relative_name,
    case replace({{ mogov.json_str('payload', '$.role') }}, 'http://www.wikidata.org/prop/direct/', '')
        when 'P169' then 'chief executive'
        when 'P1037' then 'director/manager'
        when 'P3320' then 'board member'
        when 'P488' then 'chairperson'
        when 'P112' then 'founder'
        when 'P127' then 'owner'
    end as leadership_role,
    {{ mogov.json_str('payload', '$.orgLabel') }} as organization,
    {{ strip.format(mogov.json_str('payload', '$.org')) }} as organization_qid,
    {{ mogov.json_str('payload', '$.positionLabel') }} as relative_position
from {{ source('raw', 'wikidata_relatives') }}
