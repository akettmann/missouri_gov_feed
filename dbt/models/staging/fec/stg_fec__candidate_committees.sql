-- Candidate -> committee links: authorized committees from the FEC linkage file, plus sponsored committees
-- (leadership PACs) from the FEC API.
select distinct
    cand_id as candidate_id,
    cmte_id as committee_id,
    cmte_dsgn as designation,
    'linkage' as link_source
from {{ source('fec', 'cand_cmte_links') }}

union

select distinct
    {{ mogov.json_str('payload', '$.sponsor_candidate_id') }} as candidate_id,
    {{ mogov.json_str('payload', '$.committee_id') }} as committee_id,
    {{ mogov.json_str('payload', '$.designation') }} as designation,
    'sponsor' as link_source
from {{ source('fec', 'sponsored_committees') }}
