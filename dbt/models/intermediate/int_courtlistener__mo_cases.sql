{{ config(enabled=var('cl_case_bulk', false)) }}
-- One row per opinion cluster in a tracked Missouri state or federal court (CourtListener bulk export),
-- with its docket and court.
select
    cl.cluster_id,
    d.court_id,
    ct.court_name as court,
    coalesce(cl.case_name, nullif(d.case_name, '')) as case_name,
    d.docket_number,
    cl.date_filed,
    cl.judges_text,
    cl.attorneys_text,
    cl.disposition,
    cl.publication_status,
    'https://www.courtlistener.com/opinion/' || cl.cluster_id || '/' || coalesce(cl.slug, '') || '/' as source_url
from {{ ref('stg_courtlistener__mo_clusters') }} as cl
inner join {{ ref('stg_courtlistener__mo_dockets') }} as d on cl.docket_id = d.docket_id
left join {{ ref('stg_courtlistener__courts') }} as ct on d.court_id = ct.court_id
