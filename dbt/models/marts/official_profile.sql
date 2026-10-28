-- One row per current official: headline facts plus, for each requested category, how many records the
-- pipeline holds and a coverage status explaining gaps:
--   available        records found
--   none found       source covers this official, nothing matched
--   not applicable   category doesn't apply to this office
--   not public       required by law but not published online (obtainable by records request)
--   no source        no machine-readable source exists or is accessible
{% set facts = [
    ('votes', 'fct_votes'),
    ('donations', 'fct_campaign_finance'),
    ('lobbyist_gifts', 'fct_lobbyist_gifts'),
    ('disclosures', 'fct_disclosures'),
    ('bias_indicators', 'fct_bias_indicators'),
    ('past_offices', 'fct_office_history'),
    ('commercial_ties', 'fct_commercial_ties'),
    ('family_ties', 'fct_family_ties'),
    ('cases', 'fct_case_history'),
    ('voluntary_disclosures', 'fct_voluntary_disclosures'),
] %}

with
{% for name, model in facts %}
    {{ name }}_n as (
        select
            official_id,
            count(*) as n
        from {{ ref(model) }}
        {% if model == 'fct_disclosures' %}
            where is_latest_version
        {% endif %}
        group by 1
    ),
{% endfor %}

legal as (
    select distinct official_id from {{ ref('fct_legal_careers') }}
),

base as (
    select
        o.*,
        o.office in ('us_house', 'us_senate') as is_congress,
        o.office in ('state_house', 'state_senate') as is_legislator,
        o.office in ('us_district_court', 'us_court_of_appeals') as is_federal_judge,
        o.office like 'mo_%' as is_state_judge,
        l.official_id is not null as is_judge_or_lawyer
    from {{ ref('dim_official') }} as o
    left join legal as l on o.official_id = l.official_id
)

select
    b.official_id,
    b.full_name,
    b.party,
    b.level,
    b.office,
    b.office_title,
    b.district,
    b.is_judge_or_lawyer,
    {% for name, model in facts %}
        coalesce({{ name }}_n.n, 0) as n_{{ name }},
    {% endfor %}
    -- coverage -------------------------------------------------------------------------------------
    case
        when votes_n.n > 0 then 'available'
        when b.is_legislator or b.is_congress then 'none found'
        else 'not applicable'
    end as votes_status,
    case
        when donations_n.n > 0 then 'available'
        when b.is_federal_judge or b.office in ('mo_supreme_court', 'mo_court_of_appeals') then 'not applicable'
        when b.level = 'federal' then 'none found'
        else 'none found (no MEC committee linked to this official)'
    end as donations_status,
    case
        when disclosures_n.n > 0 then 'available'
        when b.is_congress or b.is_federal_judge then 'none found'
        when b.level in (
            'state', 'local') then 'not public (MO personal financial disclosure: Sunshine Law request to '
        || case when b.is_state_judge then 'Clerk of the Supreme Court' else 'Missouri Ethics Commission' end || ')'
    end as disclosures_status,
    case
        when voluntary_disclosures_n.n > 0 then 'available'
        else 'none recorded (no public list exists)'
    end as voluntary_disclosures_status,
    case
        when bias_indicators_n.n > 0 then 'available'
        when b.is_legislator or b.is_congress then 'none found'
        else 'not applicable'
    end as bias_status,
    case
        when commercial_ties_n.n > 0 then 'available'
        when b.is_congress or b.is_federal_judge then 'none found'
        else 'not public (state disclosures not online; MO SOS business registry not machine-accessible)'
    end as commercial_ties_status,
    case when family_ties_n.n > 0 then 'available' else 'none found' end as family_ties_status,
    case
        when cases_n.n > 0 then 'available'
        when b.is_judge_or_lawyer then 'none found (CourtListener covers appellate + federal courts only)'
        else 'not applicable'
    end as cases_status
from base as b
{% for name, model in facts %}
    left join {{ name }}_n on b.official_id = {{ name }}_n.official_id
{% endfor %}
