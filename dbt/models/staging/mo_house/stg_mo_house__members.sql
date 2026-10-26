-- MO House members per session (end-of-session snapshot from the House XML export).
select
    session_code,
    2000 + {{ dbt.safe_cast(dbt.right('left(session_code, 2)', 2), dbt.type_int()) }} as session_year,
    district,
    {{ dbt.safe_cast('district_number', dbt.type_int()) }} as district_number,
    last_name,
    first_name,
    {{ mogov.normalize_party('party') }} as party,
    {{ dbt.safe_cast('year_elected', dbt.type_int()) }} as year_elected,
    hometown,
    biography,
    {{ mogov.regex_extract('photo_link', 'id=([0-9]+)') }} as house_member_id,
    upper(last_name) as last_name_upper
from {{ source('mo_house', 'xml_members') }}
where last_name is not null
