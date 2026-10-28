-- Coverage status text is shown to readers (cell and sentence on every profile). It must carry no instructions to the
-- maintainer: no seed or file paths, no "add finds" or to-do notes (#829).
with statuses as (
    select
        official_id,
        'votes_status' as status_column,
        votes_status as status
    from {{ ref('official_profile') }}
    union all
    select
        official_id,
        'donations_status' as status_column,
        donations_status as status
    from {{ ref('official_profile') }}
    union all
    select
        official_id,
        'disclosures_status' as status_column,
        disclosures_status as status
    from {{ ref('official_profile') }}
    union all
    select
        official_id,
        'voluntary_disclosures_status' as status_column,
        voluntary_disclosures_status as status
    from {{ ref('official_profile') }}
    union all
    select
        official_id,
        'bias_status' as status_column,
        bias_status as status
    from {{ ref('official_profile') }}
    union all
    select
        official_id,
        'commercial_ties_status' as status_column,
        commercial_ties_status as status
    from {{ ref('official_profile') }}
    union all
    select
        official_id,
        'family_ties_status' as status_column,
        family_ties_status as status
    from {{ ref('official_profile') }}
    union all
    select
        official_id,
        'cases_status' as status_column,
        cases_status as status
    from {{ ref('official_profile') }}
)

select
    official_id,
    status_column,
    status
from statuses
where
    lower(status) like '%seeds/%'
    or lower(status) like '%.csv%'
    or lower(status) like '%add finds%'
    or lower(status) like '%todo%'
