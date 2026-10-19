-- Living people Wikidata records as holding a Missouri office; used to find QIDs for officials by name.
select distinct
    replace({{ mogov.json_str('payload', '$.person') }}, 'http://www.wikidata.org/entity/', '') as qid,
    {{ mogov.json_str('payload', '$.personLabel') }} as label,
    {{ mogov.json_str('payload', '$.positionLabel') }} as position_label
from {{ source('wikidata', 'mo_officeholders') }}
