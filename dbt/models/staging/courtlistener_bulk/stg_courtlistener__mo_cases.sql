{{ config(enabled=var('cl_case_bulk', false)) }}
-- One row per opinion cluster in a Missouri state or federal court (CourtListener bulk export), with its
-- docket. judges / attorneys are CourtListener's free-text fields as printed in the opinion.
select
    cl.id as cluster_id,
    d.court_id,
    ct.full_name as court,
    coalesce(nullif(cl.case_name, ''), nullif(d.case_name, ''), cl.case_name_full) as case_name,
    d.docket_number,
    {{ dbt.safe_cast('cl.date_filed', 'date') }} as date_filed,
    nullif(trim(cl.judges), '') as judges_text,
    nullif(trim(cl.attorneys), '') as attorneys_text,
    nullif(trim(cl.disposition), '') as disposition,
    cl.precedential_status as publication_status,
    'https://www.courtlistener.com/opinion/' || cl.id || '/' || coalesce(cl.slug, '') || '/' as source_url
from {{ source('raw', 'cl_mo_opinion_clusters') }} as cl
inner join {{ source('raw', 'cl_mo_dockets') }} as d on cl.docket_id = d.id
left join {{ source('raw', 'cl_courts') }} as ct on d.court_id = ct.id
