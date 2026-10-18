-- Cases involving officials who are or were judges or lawyers (CourtListener opinion index), with role and
-- outcome. role: 'judge' (authored or sat on the panel) or 'attorney' (named as counsel in the opinion).
-- outcome: CourtListener's disposition field when present, else the decree word found at the end of the
-- lead opinion (AFFIRMED / REVERSED / REMANDED / DISMISSED ...), else null. Both need COURTLISTENER_TOKEN.
-- Caveats: surname-only judge searches can catch a same-named judge on the same court; attorney text
-- names an Attorney General on every brief their office filed (role 'attorney' = office of record).
with cases as (
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
)

select
    official_id,
    role,
    case_name,
    court,
    court_id,
    docket_number,
    date_filed,
    nullif(trim(coalesce(disposition, '')), '') as disposition,
    coalesce(
        nullif(trim(coalesce(disposition, '')), ''),
        case
            when
                opinion_tail like '%AFFIRMED IN PART%' or opinion_tail like '%REVERSED IN PART%'
                then 'affirmed in part, reversed in part'
            when
                opinion_tail like '%REVERSED AND REMANDED%' or opinion_tail like '%REVERSE AND REMAND%'
                then 'reversed and remanded'
            when opinion_tail like '%VACATED%' then 'vacated'
            when opinion_tail like '%REVERSED%' then 'reversed'
            when opinion_tail like '%REMANDED%' then 'remanded'
            when opinion_tail like '%AFFIRMED%' or opinion_tail like '%IS AFFIRMED%' then 'affirmed'
            when opinion_tail like '%DISMISSED%' then 'dismissed'
            when opinion_tail like '%PERMANENT WRIT%' or opinion_tail like '%WRIT IS MADE ABSOLUTE%' then 'writ granted'
            when opinion_tail like '%WRIT%DENIED%' or opinion_tail like '%QUASHED%' then 'writ denied'
        end
    ) as outcome,
    judges_text,
    attorneys_text,
    publication_status,
    source_url
from cases
