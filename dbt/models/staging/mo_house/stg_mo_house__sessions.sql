-- The House's own names for its legislative sessions (SESSIONLIST: "2025 1st Extraordinary Session", "2018 Special
-- Session"). Every session's SESSIONLIST repeats the full history, so the copy from the newest session wins; the
-- House numbers extraordinary sessions irregularly, so the code's last digit cannot be turned into a name.
with sessions as (
    select
        session_code as listed_in,
        session_id as session_code,
        trim(name) as session_name,
        {{ dbt.safe_cast('session_year', dbt.type_int()) }} as session_year,
        session_type,
        general_assembly,
        session_of_general_assembly
    from {{ source('mo_house', 'xml_sessions') }}
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
