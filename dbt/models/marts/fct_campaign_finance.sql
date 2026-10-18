-- Donations to and from each official's campaign committees.
--   direction = 'received': money given to the official's committee(s)
--   direction = 'given':    contributions made by the official's committee(s) or leadership PAC
-- Federal: FEC committee contributions (pas2) for every FEC candidate ID the official has used.
-- State/local: MEC itemized contributions/expenditures (TAP mirror, 2011-2022) for name-matched committees.
-- Individual federal donors are summarized in fct_federal_donor_summary rather than listed.
with fec_ids as (
    select
        o.official_id,
        f.fec_candidate_id
    from {{ ref('dim_official') }} as o
    inner join {{ ref('stg_congress__fec_ids') }} as f on o.bioguide_id = f.bioguide_id
),

fec_committees as (
    select distinct
        i.official_id,
        l.committee_id
    from fec_ids as i
    inner join {{ ref('stg_fec__candidate_committees') }} as l on i.fec_candidate_id = l.candidate_id
),

fec_received as (
    select
        i.official_id,
        'received' as direction,
        'federal' as level,
        c.transaction_date,
        c.amount,
        g.committee_name as counterparty,
        g.connected_organization as counterparty_organization,
        coalesce(g.committee_type, 'committee') as counterparty_type,
        c.transaction_kind as kind,
        'FEC' as source,
        'exact id' as match_confidence,
        'https://www.fec.gov/data/receipts/?committee_id=' || c.giving_committee_id as source_url
    from {{ ref('stg_fec__committee_contributions') }} as c
    inner join fec_ids as i on c.candidate_id = i.fec_candidate_id
    left join {{ ref('stg_fec__committees') }} as g on c.giving_committee_id = g.committee_id
    where c.transaction_kind = 'direct contribution'
),

fec_given as (
    select
        fc.official_id,
        'given' as direction,
        'federal' as level,
        c.transaction_date,
        c.amount,
        coalesce(c.recipient_name, r.committee_name) as counterparty,
        cast(null as {{ dbt.type_string() }}) as counterparty_organization,
        'candidate committee' as counterparty_type,
        c.transaction_kind || coalesce(' (from ' || g.committee_name || ')', '') as kind,
        'FEC' as source,
        'exact id' as match_confidence,
        'https://www.fec.gov/data/disbursements/?committee_id=' || c.giving_committee_id as source_url
    from {{ ref('stg_fec__committee_contributions') }} as c
    inner join fec_committees as fc on c.giving_committee_id = fc.committee_id
    left join {{ ref('stg_fec__committees') }} as g on c.giving_committee_id = g.committee_id
    left join {{ ref('stg_fec__committees') }} as r on c.recipient_committee_id = r.committee_id
),

mec_received as (
    select
        m.official_id,
        'received' as direction,
        'state' as level,
        c.contribution_date as transaction_date,
        c.amount,
        c.contributor_name as counterparty,
        coalesce(c.contributor_company, c.contributor_employer) as counterparty_organization,
        c.contributor_type as counterparty_type,
        case c.contribution_kind when 'I' then 'in-kind' when 'In-Kind' then 'in-kind' else 'monetary' end
        || ' to ' || m.committee_name as kind,
        'MEC (via Accountability Project)' as source,
        m.confidence as match_confidence,
        'https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=' || m.mec_committee_id as source_url
    from {{ ref('stg_mec__contributions') }} as c
    inner join {{ ref('int_mec__official_committees') }} as m on c.mec_committee_id = m.mec_committee_id
),

mec_given as (
    select
        m.official_id,
        'given' as direction,
        'state' as level,
        e.expenditure_date as transaction_date,
        e.amount,
        e.payee_name as counterparty,
        cast(null as {{ dbt.type_string() }}) as counterparty_organization,
        case when lower(e.purpose) like '%charit%' then 'charity' else 'committee or candidate' end
            as counterparty_type,
        lower(e.purpose) || ' from ' || m.committee_name as kind,
        'MEC (via Accountability Project)' as source,
        m.confidence as match_confidence,
        'https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=' || m.mec_committee_id as source_url
    from {{ ref('stg_mec__expenditures') }} as e
    inner join {{ ref('int_mec__official_committees') }} as m on e.mec_committee_id = m.mec_committee_id
    where
        lower(e.purpose) like '%contribution%'
        and lower(e.purpose) not like '%fee%'
        and lower(e.purpose) not like '%refund%'
        and lower(e.purpose) not like '%return%'
){% if var('mec_direct', false) %},

-- MEC direct exports (report years 2023+; the TAP mirror covers report years through 2022, so no overlap)
mec_direct_received as (
    select
        m.official_id,
        'received' as direction,
        'state' as level,
        c.contribution_date as transaction_date,
        c.amount,
        c.contributor_name as counterparty,
        c.contributor_company as counterparty_organization,
        c.contributor_type as counterparty_type,
        lower(c.contribution_kind) || ' to ' || m.committee_name as kind,
        'MEC' as source,
        m.confidence as match_confidence,
        'https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=' || m.mec_committee_id as source_url
    from {{ ref('stg_mec_direct__contributions') }} as c
    inner join {{ ref('int_mec__official_committees') }} as m on c.mec_committee_id = m.mec_committee_id
),

mec_direct_given as (
    select
        m.official_id,
        'given' as direction,
        'state' as level,
        c.contribution_date as transaction_date,
        c.amount,
        c.recipient_name as counterparty,
        cast(null as {{ dbt.type_string() }}) as counterparty_organization,
        'committee or candidate' as counterparty_type,
        lower(c.contribution_kind) || ' contribution from ' || m.committee_name as kind,
        'MEC' as source,
        m.confidence as match_confidence,
        'https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=' || m.mec_committee_id as source_url
    from {{ ref('stg_mec_direct__contributions_made') }} as c
    inner join {{ ref('int_mec__official_committees') }} as m on c.mec_committee_id = m.mec_committee_id
)
{% endif %}

{% set cols = 'official_id, direction, level, transaction_date, amount, counterparty, counterparty_organization,
    counterparty_type, kind, source, match_confidence, source_url' %}
select {{ cols }} from fec_received
union all
select {{ cols }} from fec_given
union all
select {{ cols }} from mec_received
union all
select {{ cols }} from mec_given
{% if var('mec_direct', false) %}
union all
select {{ cols }} from mec_direct_received
union all
select {{ cols }} from mec_direct_given
{% endif %}
