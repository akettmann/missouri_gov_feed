{{ config(enabled=var('mec_direct', false)) }}
-- MEC's own candidate <-> committee crosswalk (CF12 election search export), one row per candidacy.
-- cells: [MECID, committee name, candidate name, party, office sought, status]
with rows_ as (
    select
        {{ mogov.json_str('payload', '$.election_date') }} as election_date_text,
        {{ mogov.json_str('payload', '$.cells[0]') }} as mec_committee_id,
        {{ mogov.json_str('payload', '$.cells[1]') }} as committee_name,
        {{ mogov.json_str('payload', '$.cells[2]') }} as candidate_name,
        {{ mogov.json_str('payload', '$.cells[3]') }} as party,
        {{ mogov.json_str('payload', '$.cells[4]') }} as office_sought,
        {{ mogov.json_str('payload', '$.cells[5]') }} as status
    from {{ source('mec', 'candidate_committees') }}
)

select
    *,
    {{ mogov.parse_date('election_date_text', '%m/%d/%Y') }} as election_date,
    {{ mogov.name_key('candidate_name') }} as candidate_key
from rows_
where mec_committee_id is not null and candidate_name is not null
