-- Two aliases that differ only by case or punctuation ("HRCC, Inc." and "hrcc inc") are the same donor name to the
-- crosswalk, so none may be listed twice (least of all for different committees): the key is what gets matched.
select
    {{ mogov.name_key('alias') }} as alias_key,
    count(*) as n_rows
from {{ ref('committee_donor_aliases') }}
group by {{ mogov.name_key('alias') }}
having count(*) > 1
