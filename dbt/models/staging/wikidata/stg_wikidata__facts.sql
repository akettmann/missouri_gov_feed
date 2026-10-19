-- Wikidata facts about Missouri officials, normalized to (qid, fact_kind, value, value_qid, dates).
{% set qid = "replace(" ~ mogov.json_str('payload', '$.person') ~ ", 'http://www.wikidata.org/entity/', '')" %}
{% set vqid = "replace({}, 'http://www.wikidata.org/entity/', '')" %}

select
    {{ qid }} as qid,
    'position held' as fact_kind,
    {{ mogov.json_str('payload', '$.positionLabel') }} as value,
    {{ vqid.format(mogov.json_str('payload', '$.position')) }} as value_qid,
    {{ mogov.json_str('payload', '$.districtLabel') }} as qualifier,
    {{ dbt.safe_cast("left(" ~ mogov.json_str('payload', '$.start') ~ ", 10)", 'date') }} as start_date,
    {{ dbt.safe_cast("left(" ~ mogov.json_str('payload', '$.end') ~ ", 10)", 'date') }} as end_date
from {{ source('wikidata', 'positions') }}

union all

select
    {{ qid }} as qid,
    case replace({{ mogov.json_str('payload', '$.prop') }}, 'http://www.wikidata.org/prop/direct/', '')
        when 'P106' then 'occupation'
        when 'P108' then 'employer'
        when 'P102' then 'political party'
        when 'P69' then 'educated at'
        when 'P463' then 'member of'
    end as fact_kind,
    {{ mogov.json_str('payload', '$.valueLabel') }} as value,
    {{ vqid.format(mogov.json_str('payload', '$.value')) }} as value_qid,
    cast(null as {{ dbt.type_string() }}) as qualifier,
    cast(null as date) as start_date,
    cast(null as date) as end_date
from {{ source('wikidata', 'attributes') }}

union all

select
    {{ qid }} as qid,
    case replace({{ mogov.json_str('payload', '$.role') }}, 'http://www.wikidata.org/prop/direct/', '')
        when 'P169' then 'chief executive of'
        when 'P1037' then 'director/manager of'
        when 'P3320' then 'board member of'
        when 'P488' then 'chairperson of'
        when 'P112' then 'founder of'
        when 'P127' then 'owner of'
    end as fact_kind,
    {{ mogov.json_str('payload', '$.orgLabel') }} as value,
    {{ vqid.format(mogov.json_str('payload', '$.org')) }} as value_qid,
    cast(null as {{ dbt.type_string() }}) as qualifier,
    cast(null as date) as start_date,
    cast(null as date) as end_date
from {{ source('wikidata', 'own_leadership') }}
