-- Spellings of a donor committee that normalize to the same committee_key ("MO Chamber PAC", "Missouri Chamber
-- PAC") should resolve to one MECID in a given year. The exception is committees whose own filed names already
-- tell them apart: "MO Values PAC" (C201504) and "Missouri Values PAC" (C232626) are two committees, and each
-- spelling matches its own by exact name. So a conflict fails only when a looser tier (normalized or core name)
-- produced one of the links: that link contradicts another spelling's and is likely wrong.
-- Measured October 2026: 4 keys have two IDs in a year, all from exact-name matches; 0 involve a looser tier.
select
    {{ mogov.committee_key('donor_committee_name') }} as donor_key,
    contribution_year,
    count(distinct mec_committee_id) as n_ids
from {{ ref('int_mec__donor_committees') }}
where match_status = 'matched'
group by {{ mogov.committee_key('donor_committee_name') }}, contribution_year
having
    count(distinct mec_committee_id) > 1
    and max(case when match_method in ('normalized name', 'core name') then 1 else 0 end) = 1
