-- Sponsors of each House bill as the XML lists them: sponsor, co-sponsors, handlers and House/Senate
-- conferees. District numbers are the House's: senators appear as 200 + their senate district.
select
    b.session_code,
    b.session_year,
    b.bill,
    {{ mogov.json_str('s.value', '$.SponsorType[0]') }} as sponsor_type,
    {{ mogov.json_str('s.value', '$.FullName[0]') }} as sponsor_name,
    {{ dbt.safe_cast(mogov.json_str('s.value', '$.District[0]'), dbt.type_int()) }} as sponsor_district
from {{ ref('stg_mo_house__bills') }} as b
cross join lateral {{ mogov.json_elements('b.bill_doc', '$.Sponsor') }} as s
