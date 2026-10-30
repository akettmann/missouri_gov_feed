-- How each official's state campaign committees spent their money: itemized expenditures (payee, purpose,
-- amount). TAP mirror for report years through 2022; MEC's own CD3 Part B export (over $100) for 2023+ when
-- the MEC loader has run, so the two never overlap. Committees are attributed as in fct_campaign_finance
-- (int_mec__official_committees). TAP's expenditures include contributions to other committees, which
-- fct_campaign_finance also lists as direction 'given'; MEC's export reports those separately (Part C).
-- Grain: (official_id, source_record_id), the MEC expenditure record id (a committee can be attributed to
-- more than one official, so the official is part of the key).
with tap as (
    select
        m.official_id,
        e.expenditure_date,
        e.amount,
        e.payee_name,
        e.payee_city,
        e.payee_state,
        e.purpose,
        e.expenditure_type,
        m.committee_name,
        m.mec_committee_id,
        m.confidence as match_confidence,
        'MEC (via Accountability Project)' as source,
        'tap_cd3_b:' || cast(e.record_id as {{ dbt.type_string() }}) as source_record_id
    from {{ ref('stg_tap_mec__expenditures') }} as e
    inner join {{ ref('int_mec__official_committees') }} as m on e.mec_committee_id = m.mec_committee_id
){% if var('mec_direct', false) %}
    ,

    direct as (
        select
            m.official_id,
            e.expenditure_date,
            e.amount,
            e.payee_name,
            e.payee_city,
            e.payee_state,
            e.purpose,
            e.expenditure_type,
            m.committee_name,
            m.mec_committee_id,
            m.confidence as match_confidence,
            'MEC' as source,
            'mec_cd3_b:' || cast(e.record_id as {{ dbt.type_string() }}) as source_record_id
        from {{ ref('stg_mec__expenditures') }} as e
        inner join {{ ref('int_mec__official_committees') }} as m on e.mec_committee_id = m.mec_committee_id
    )
{% endif %}

{% set cols = 'official_id, expenditure_date, amount, payee_name, payee_city, payee_state, purpose,
    expenditure_type, committee_name, mec_committee_id, match_confidence, source, source_record_id' %}
select
    {{ cols }},
    'https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=' || mec_committee_id as source_url
from (
    select {{ cols }} from tap
    {% if var('mec_direct', false) %}
        union all
        select {{ cols }} from direct
    {% endif %}
) as spending
