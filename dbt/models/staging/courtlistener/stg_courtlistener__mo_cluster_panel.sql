{{ config(enabled=var('cl_case_bulk', false)) }}
-- CourtListener bulk opinion panels: which judges (person ids) sat on each cluster.
select
    opinioncluster_id as cluster_id,
    person_id as cl_person_id
from {{ source('courtlistener', 'mo_cluster_panel') }}
