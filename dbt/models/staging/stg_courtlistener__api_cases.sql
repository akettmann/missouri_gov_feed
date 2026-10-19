-- CourtListener REST search hits per official judge/lawyer (stage-2 courtlistener_cases loader), with the
-- cluster's disposition and the lead opinion's last ~1,500 characters when COURTLISTENER_TOKEN was set.
select
    {{ mogov.json_str('payload', '$.official_id') }} as official_id,
    {{ mogov.json_str('payload', '$.role_searched') }} as role,
    {{ mogov.json_str('payload', '$.cluster_id') }} as cluster_id,
    {{ mogov.json_str('payload', '$.caseName') }} as case_name,
    {{ mogov.json_str('payload', '$.court') }} as court,
    {{ mogov.json_str('payload', '$.court_id') }} as court_id,
    {{ mogov.json_str('payload', '$.docketNumber') }} as docket_number,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.dateFiled'), 'date') }} as date_filed,
    {{ mogov.json_str('payload', '$.judge') }} as judges_text,
    {{ mogov.json_str('payload', '$.attorney') }} as attorneys_text,
    {{ mogov.json_str('payload', '$.status') }} as publication_status,
    {{ mogov.json_str('payload', '$.disposition') }} as disposition,
    upper({{ mogov.json_str('payload', '$.opinion_tail') }}) as opinion_tail,
    'https://www.courtlistener.com' || {{ mogov.json_str('payload', '$.absolute_url') }} as source_url
from {{ source('raw', 'cl_cases') }}
