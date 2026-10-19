-- U.S. House Clerk financial disclosure index (all members/candidates nationally).
-- FilingType: O annual, A amendment, P periodic transaction report, C candidate, T termination, X extension.
select
    {{ mogov.json_str('payload', '$.DocID') }} as doc_id,
    {{ mogov.json_str('payload', '$.Prefix') }} as prefix,
    {{ mogov.json_str('payload', '$.First') }} as first_name,
    {{ mogov.json_str('payload', '$.Last') }} as last_name,
    {{ mogov.json_str('payload', '$.StateDst') }} as state_district,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.Year'), dbt.type_int()) }} as filing_year,
    {{ mogov.json_str('payload', '$.FilingType') }} as filing_type,
    case {{ mogov.json_str('payload', '$.FilingType') }}
        when 'O' then 'annual report'
        when 'A' then 'amended report'
        when 'P' then 'periodic transaction report'
        when 'C' then 'candidate report'
        when 'T' then 'termination report'
        when 'X' then 'extension request'
        when 'D' then 'candidate threshold notice'
        else 'other'
    end as filing_kind,
    {{ mogov.parse_date(mogov.json_str('payload', '$.FilingDate'), '%m/%d/%Y') }} as filing_date,
    'https://disclosures-clerk.house.gov/public_disc/'
    || case when {{ mogov.json_str('payload', '$.FilingType') }} = 'P' then 'ptr-pdfs/' else 'financial-pdfs/' end
    || {{ mogov.json_str('payload', '$.Year') }} || '/' || {{ mogov.json_str('payload', '$.DocID') }} || '.pdf'
        as document_url
from {{ source('house_fd', 'index') }}
