-- Federal judges' financial disclosure reports (AO-10) as indexed by CourtListener, linked to FJC ids.
select
    fd.id as disclosure_id,
    fd.person_id as cl_person_id,
    p.fjc_id,
    p.name_first,
    p.name_last,
    {{ dbt.safe_cast('fd.year', dbt.type_int()) }} as report_year,
    fd.report_type,
    fd.is_amended = 't' as is_amended,
    fd.has_been_extracted = 't' as has_been_extracted,
    'https://storage.courtlistener.com/' || fd.filepath as document_url
from {{ source('raw', 'cl_financial_disclosures') }} as fd
inner join {{ source('raw', 'cl_people') }} as p on fd.person_id = p.id
