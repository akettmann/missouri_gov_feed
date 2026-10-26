-- The House's own names for its legislative sessions (SESSIONLIST: "2025 1st Extraordinary Session", "2018 Special
-- Session"). Every session's SESSIONLIST repeats the full history, so the copy from the newest session wins; the
-- House numbers extraordinary sessions irregularly, so the code's last digit cannot be turned into a name.
with src as (
    select
        {{ mogov.json_str('payload', '$.session_code') }} as listed_in,
        {{ mogov.json_fragment('payload', '$.doc') }} as doc
    from {{ source('mo_house', 'lists') }}
    where {{ mogov.json_str('payload', '$.list') }} = 'SESSIONLIST'
),

sessions as (
    select
        s.listed_in,
        {{ mogov.json_str('e.value', '$.ID[0]') }} as session_code,
        trim({{ mogov.json_str('e.value', '$.Name[0]') }}) as session_name,
        {{ dbt.safe_cast(mogov.json_str('e.value', '$.SessionYear[0]'), dbt.type_int()) }} as session_year,
        {{ mogov.json_str('e.value', '$.SessionCode[0]') }} as session_type,
        {{ mogov.json_str('e.value', '$.GeneralAssembly[0]') }} as general_assembly,
        {{ mogov.json_str('e.value', '$.SessionOfGeneralAssembly[0]') }} as session_of_general_assembly
    from src as s
    cross join lateral {{ mogov.json_elements('s.doc', '$.Session') }} as e
),

ranked as (
    select
        *,
        row_number() over (partition by session_code order by listed_in desc) as rn
    from sessions
)

select
    session_code,
    session_name,
    session_year,
    session_type,
    general_assembly,
    session_of_general_assembly
from ranked
where rn = 1
