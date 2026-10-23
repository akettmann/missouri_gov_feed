-- Itemized contributions received by Missouri committees from both MEC feeds: the TAP mirror (contribution
-- years 2011-2022) and, when the opt-in loader has run, MEC's direct export (report years 2023+, so the two
-- don't overlap; see fct_campaign_finance). mec_committee_id is always the receiving committee. A committee
-- donor is identified only by contributor_committee_name: MEC records no MECID for it.
-- MECIDs are upper-cased: a few rows carry "c000525" for C000525.
with tap as (
    select
        upper(trim(mec_committee_id)) as mec_committee_id,
        committee_name,
        contributor_name,
        contributor_type,
        contributor_committee_name,
        contributor_company,
        contributor_employer,
        amount,
        contribution_date,
        coalesce(contribution_year, cast(extract(year from contribution_date) as {{ dbt.type_int() }}))
            as contribution_year,
        'MEC (via Accountability Project)' as source
    from {{ ref('stg_tap_mec__contributions') }}
    where mec_committee_id is not null
){% if var('mec_direct', false) %},

direct as (
    select
        upper(trim(mec_committee_id)) as mec_committee_id,
        committee_name,
        contributor_name,
        contributor_type,
        contributor_committee_name,
        contributor_company,
        contributor_employer,
        amount,
        contribution_date,
        contribution_year,
        'MEC' as source
    from {{ ref('stg_mec__contributions') }}
    where mec_committee_id is not null
)
{% endif %}

select * from tap
{% if var('mec_direct', false) %}
    union all
    select * from direct
{% endif %}
