-- Federal judges' financial disclosure reports (AO-10) as indexed by CourtListener, one row per report.
select
    id as disclosure_id,
    person_id as cl_person_id,
    {{ dbt.safe_cast('year', dbt.type_int()) }} as report_year,
    report_type,
    is_amended = 't' as is_amended,
    has_been_extracted = 't' as has_been_extracted,
    'https://storage.courtlistener.com/' || filepath as document_url
from {{ source('raw', 'cl_financial_disclosures') }}
