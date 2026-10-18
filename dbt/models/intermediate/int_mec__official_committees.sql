-- Missouri Ethics Commission committees attributed to current state/local officials by committee name
-- (e.g. "Nicole Galloway For Missouri", "Friends of Wesley Bell"). TAP's mirror has no candidate<->
-- committee crosswalk, so this is a name match, labeled by confidence:
--   high    committee name contains the official's first and last name
--   medium  named surname-first ("Riggs for Missouri", "Friends of Riggs", "Riggs Committee"), no other
--           current official shares that surname, and it isn't a local-office committee ("... for Sheriff").
--           A different first name anywhere in the name ("Committee to Elect Caleb Rowden") never matches.
-- When the MEC loader has run, its CF12 crosswalk (exact MECID<->candidate) should replace this.
with committees as (
    select distinct
        mec_committee_id,
        committee_name,
        ' ' || {{ mogov.name_key('committee_name') }} || ' ' as committee_key
    from {{ ref('stg_mec__contributions') }}
    where mec_committee_id is not null
),

officials as (
    select distinct
        official_id,
        family_key,
        given_key
    from {{ ref('int_officials__name_keys') }}
    where level in ('state', 'local') and length(family_key) >= 3
),

unique_surnames as (
    select family_key
    from officials
    group by 1
    having count(distinct official_id) = 1
),

matches as (
    select
        o.official_id,
        c.mec_committee_id,
        c.committee_name,
        case
            when c.committee_key like '% ' || o.given_key || ' %' then 'high'
            else 'medium'
        end as confidence
    from committees as c
    inner join officials as o on c.committee_key like '% ' || o.family_key || ' %'
    where
        c.committee_key like '% ' || o.given_key || ' %'
        or (
            o.family_key in (select u.family_key from unique_surnames as u)
            and (
                c.committee_key like ' ' || o.family_key || ' for %'
                or c.committee_key like ' friends of ' || o.family_key || ' %'
                or c.committee_key like ' ' || o.family_key || ' committee %'
                or c.committee_key = ' ' || o.family_key || ' '
            )
            {% for word in ['sheriff', 'prosecutor', 'county', 'mayor', 'council', 'alderman', 'clerk', 'assessor',
                            'collector', 'commissioner', 'coroner', 'treasurer', 'recorder', 'school', 'board',
                            'police', 'chief', 'ward', 'city', 'township', 'district'] %}
                and c.committee_key not like '% {{ word }} %'
            {% endfor %}
        )
),

{% if var('mec_direct', false) %}
-- Exact links from MEC's own candidate<->committee crosswalk: same candidate name, and the office sought
-- fits the official's current office (or the candidate name is unique in the crosswalk).
crosswalk_names as (
    select
        candidate_key,
        count(distinct mec_committee_id) as n_committees,
        count(distinct office_sought) as n_offices
    from {{ ref('stg_mec_direct__candidate_committees') }}
    group by 1
),

crosswalk as (
    select distinct
        k.official_id,
        x.mec_committee_id,
        x.committee_name,
        'exact (MEC crosswalk)' as confidence
    from {{ ref('stg_mec_direct__candidate_committees') }} as x
    inner join {{ ref('int_officials__name_keys') }} as k on x.candidate_key = k.variant_key
    inner join crosswalk_names as n on x.candidate_key = n.candidate_key
    where
        k.level in ('state', 'local')
        and (
            n.n_offices = 1
            or (k.office = 'state_house' and x.office_sought like '%State Representative%')
            or (k.office = 'state_senate' and (x.office_sought like '%State Senator%' or x.office_sought like '%State Representative%'))
            or (k.office = 'governor' and x.office_sought like '%Governor%')
            or (k.office = 'lt_governor' and x.office_sought like '%Lieutenant Governor%')
            or (k.office = 'secretary_of_state' and x.office_sought like '%Secretary of State%')
            or (k.office = 'state_auditor' and x.office_sought like '%Auditor%')
            or (k.office = 'state_treasurer' and x.office_sought like '%Treasurer%')
            or (k.office = 'attorney_general' and x.office_sought like '%Attorney General%')
            or (k.office like 'mo_%' and x.office_sought like '%Judge%')
            or (k.office = 'mayor' and x.office_sought like '%Mayor%')
        )
),

all_matches as (
    select
        official_id,
        mec_committee_id,
        committee_name,
        confidence
    from crosswalk
    union all
    -- name heuristics only for officials the crosswalk doesn't cover
    select
        official_id,
        mec_committee_id,
        committee_name,
        confidence
    from matches
    where official_id not in (select c.official_id from crosswalk as c)
)
{% else %}
    all_matches as (
        select * from matches
    )
{% endif %}

select
    official_id,
    mec_committee_id,
    max(committee_name) as committee_name,
    -- 'exact (MEC crosswalk)' < 'high' < 'medium' alphabetically, so min() keeps the strongest
    min(confidence) as confidence
from all_matches
group by 1, 2
