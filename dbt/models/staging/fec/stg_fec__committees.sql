-- FEC committee master, latest cycle's record per committee. CMTE_DSGN: P principal campaign,
-- A authorized, D leadership PAC, J joint fundraiser, U unauthorized, B lobbyist PAC.
select
    cmte_id as committee_id,
    cmte_nm as committee_name,
    cmte_dsgn as designation,
    cmte_tp as committee_type,
    cmte_pty_affiliation as party,
    connected_org_nm as connected_organization,
    cand_id as candidate_id,
    cmte_city as city,
    cmte_st as state
from (
    select
        *,
        row_number() over (partition by cmte_id order by filename desc) as rn
    from {{ source('fec', 'committees') }}
) as ranked
where rn = 1
