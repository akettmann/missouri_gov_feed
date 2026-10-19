-- MO House members per session (end-of-session snapshot from the House XML export).
with src as (
    select
        {{ mogov.json_str('payload', '$.session_code') }} as session_code,
        {{ mogov.json_fragment('payload', '$.doc.RepresentativeData[0].RepresentativeInfo[0]') }} as info
    from {{ source('raw', 'mo_house_members') }}
)

select
    session_code,
    2000 + {{ dbt.safe_cast(dbt.right('left(session_code, 2)', 2), dbt.type_int()) }} as session_year,
    {{ mogov.json_str('info', '$.DistrictNum[0]') }} as district,
    {{ dbt.safe_cast(mogov.json_str('info', '$.DistrictNum[0]'), dbt.type_int()) }} as district_number,
    {{ mogov.json_str('info', '$.LastName[0]') }} as last_name,
    {{ mogov.json_str('info', '$.FirstName[0]') }} as first_name,
    {{ mogov.normalize_party(mogov.json_str('info', '$.Party[0]')) }} as party,
    {{ dbt.safe_cast(mogov.json_str('info', '$.YearElected[0]'), dbt.type_int()) }} as year_elected,
    {{ mogov.json_str('info', '$.Hometown[0]') }} as hometown,
    {{ mogov.json_str('info', '$.Biography[0]') }} as biography,
    {{ mogov.regex_extract(mogov.json_str('info', '$.PhotoLink[0]'), 'id=([0-9]+)') }} as house_member_id,
    upper({{ mogov.json_str('info', '$.LastName[0]') }}) as last_name_upper
from src
where {{ mogov.json_str('info', '$.LastName[0]') }} is not null
