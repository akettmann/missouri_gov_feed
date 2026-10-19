{{ config(enabled=var('cl_case_bulk', false)) }}
-- CourtListener bulk opinion clusters (one per decided case) on those dockets. judges / attorneys are
-- CourtListener's free-text fields as printed in the opinion.
select
    id as cluster_id,
    docket_id,
    coalesce(nullif(case_name, ''), case_name_full) as case_name,
    slug,
    {{ dbt.safe_cast('date_filed', 'date') }} as date_filed,
    nullif(trim(judges), '') as judges_text,
    nullif(trim(attorneys), '') as attorneys_text,
    nullif(trim(disposition), '') as disposition,
    precedential_status as publication_status
from {{ source('courtlistener', 'mo_opinion_clusters') }}
