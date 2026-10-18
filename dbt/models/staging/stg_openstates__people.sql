-- One row per Missouri person in Open States (excludes the committees folder).
with src as (
    select
        {{ mogov.json_str('payload', '$.folder') }} as folder,
        {{ mogov.json_fragment('payload', '$.doc') }} as doc
    from {{ source('raw', 'openstates_people') }}
),

-- party list is chronological; the last entry is the current affiliation
parties as (
    select
        {{ mogov.json_str('s.doc', '$.id') }} as openstates_id,
        {{ mogov.json_str('pt.value', '$.name') }} as party,
        row_number() over (partition by {{ mogov.json_str('s.doc', '$.id') }} order by pt.idx desc) as rn
    from src as s
    cross join lateral {{ mogov.json_elements('s.doc', '$.party') }} as pt
)

select
    {{ mogov.json_str('s.doc', '$.id') }} as openstates_id,
    {{ mogov.json_str('s.doc', '$.name') }} as full_name,
    {{ mogov.json_str('s.doc', '$.given_name') }} as given_name,
    {{ mogov.json_str('s.doc', '$.family_name') }} as family_name,
    {{ mogov.json_str('s.doc', '$.gender') }} as gender,
    {{ mogov.json_str('s.doc', '$.email') }} as email,
    {{ mogov.json_str('s.doc', '$.image') }} as image_url,
    pt.party,
    {{ dbt.safe_cast(mogov.json_str('s.doc', '$.birth_date'), 'date') }} as birth_date,
    {{ mogov.json_str('s.doc', '$.extras.hometown') }} as hometown,
    s.folder,
    s.folder in ('legislature', 'executive', 'municipalities') as is_current_in_openstates,
    s.doc
from src as s
left join parties as pt
    on {{ mogov.json_str('s.doc', '$.id') }} = pt.openstates_id and pt.rn = 1
where s.folder <> 'committees'
