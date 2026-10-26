-- assert_committee_donor_aliases_signed_off picks each committee's name with min(committee_name); if a committee's
-- alias rows disagreed (a typo, say) it would silently pick one. Every mec_committee_id must carry exactly one name.
select
    mec_committee_id,
    count(distinct committee_name) as n_names
from {{ ref('committee_donor_aliases') }}
group by mec_committee_id
having count(distinct committee_name) > 1
