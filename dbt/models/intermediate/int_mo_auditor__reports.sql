-- State Auditor reports with their rating and the kind of entity audited. A report has a rating only when its
-- PDF carried the sentence "the overall performance of this entity was ..." (rating_status 'ok'); 'not_read'
-- means the loader never opened a PDF for it (financial statements, monthly filing reports, follow-ups, reports
-- before the 2012 summaries). rating_level orders the Auditor's four levels (Excellent 4 ... Poor 1).
-- entity_type: 'statewide_office' when the title starts with an audited statewide office (seed
-- mo_auditor_statewide_entities), 'county' for a title ending in " County", else 'other' (state agencies, cities,
-- courts, schools, districts, statewide reports). Only a statewide office is ever linked to an officeholder.
with reports as (
    select * from {{ ref('stg_mo_auditor__reports') }}
),

ratings as (
    select * from {{ ref('stg_mo_auditor__ratings') }}
)

select
    r.report_number,
    r.report_number_display,
    r.report_year,
    r.release_date,
    r.title,
    case
        when e.office is not null then 'statewide_office'
        when lower(r.title) like '% county' then 'county'
        else 'other'
    end as entity_type,
    e.office,
    a.rating,
    case a.rating
        when 'Excellent' then 4
        when 'Good' then 3
        when 'Fair' then 2
        when 'Poor' then 1
    end as rating_level,
    coalesce(a.extraction_status, 'not_read') as rating_status,
    a.rating_sentence,
    a.page as rating_page,
    a.pdf_url as rating_pdf_url,
    r.full_report_url,
    r.citizens_summary_url
from reports as r
left join ratings as a on r.report_number = a.report_number
left join {{ ref('mo_auditor_statewide_entities') }} as e on lower(r.title) like e.title_prefix || '%'
