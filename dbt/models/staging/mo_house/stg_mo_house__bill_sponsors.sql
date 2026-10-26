-- Sponsors of each House bill as the XML lists them: sponsor, co-sponsors, handlers and House/Senate
-- conferees. District numbers are the House's: senators appear as 200 + their senate district.
select
    b.session_code,
    2000 + {{ dbt.safe_cast('left(b.session_code, 2)', dbt.type_int()) }} as session_year,
    b.bill,
    s.sponsor_type,
    s.full_name as sponsor_name,
    {{ dbt.safe_cast('s.district', dbt.type_int()) }} as sponsor_district
from {{ source('mo_house', 'xml_bills') }} as b
inner join {{ source('mo_house', 'xml_bill_sponsors') }} as s
    on b.session_code = s.session_code and b.file_name = s.file_name
