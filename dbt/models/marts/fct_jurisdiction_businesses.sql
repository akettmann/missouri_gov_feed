-- Businesses operating in each district-elected official's area: the non-government EPA-regulated facilities
-- (EPA FRS) in the district a legislator or U.S. representative is elected from, or a mayor's city, and whether
-- the official received campaign contributions from them. Judges are left out (a circuit or federal district
-- holds thousands of sites and judges take almost no organization money), as are statewide offices.
-- A donor organization matches a facility two ways:
--   same name     its company_key equals the facility's, its owner's or its parent company's (keys under four
--                 characters are not matched)
--   same company  the donor's name and the facility's, owner's or parent's name share a brand from the
--                 company_brands seed ("Ameren Missouri PAC" and a "UNION ELECTRIC CO" substation are Ameren)
with areas as (
    select
        o.official_id,
        f.registry_id,
        min(f.district_id) as district_id
    from {{ ref('fct_official_districts') }} as o
    inner join {{ ref('fct_district_facilities') }} as f on o.district_id = f.district_id
    where
        o.relation in ('elected from', 'mayor of')
        and not f.is_government
    group by o.official_id, f.registry_id
),

donors as (
    select
        official_id,
        {{ mogov.company_key("coalesce(nullif(trim(counterparty_organization), ''), counterparty)") }} as donor_key,
        min(coalesce(nullif(trim(counterparty_organization), ''), counterparty)) as donor_name,
        sum(amount) as amount,
        count(*) as n_contributions,
        min(extract(year from transaction_date)) as first_year,
        max(extract(year from transaction_date)) as last_year,
        min(source_url) as source_url,
        -- 1 when any of the money was tied to the official by a medium (name-only) match
        max(case when match_confidence = 'medium' then 1 else 0 end) as is_medium
    from {{ ref('fct_campaign_finance') }}
    where
        direction = 'received'
        and lower(coalesce(counterparty_type, '')) <> 'individual'
        and amount > 0
    group by
        official_id,
        {{ mogov.company_key("coalesce(nullif(trim(counterparty_organization), ''), counterparty)") }}
),

donor_brands as (
    select distinct
        d.official_id,
        d.donor_key,
        b.brand
    from donors as d
    inner join {{ ref('company_brands') }} as b
        on ' ' || {{ mogov.name_key('d.donor_name') }} || ' ' like '% ' || b.keyword || ' %'
),

facility_brands as (
    select distinct
        i.registry_id,
        b.brand
    from {{ ref('int_epa_frs__facilities') }} as i
    inner join {{ ref('company_brands') }} as b
        on
            ' ' || {{ mogov.name_key("coalesce(i.facility_name, '')") }} || ' ' like '% ' || b.keyword || ' %'
            or ' ' || {{ mogov.name_key("coalesce(i.owner_name, '')") }} || ' ' like '% ' || b.keyword || ' %'
            or ' ' || {{ mogov.name_key("coalesce(i.parent_company_name, '')") }} || ' ' like '% ' || b.keyword || ' %'
),

matched_donors as (
    select
        a.official_id,
        a.registry_id,
        d.donor_key,
        1 as by_name
    from areas as a
    inner join {{ ref('int_epa_frs__facilities') }} as i on a.registry_id = i.registry_id
    inner join donors as d
        on
            a.official_id = d.official_id
            and d.donor_key in (i.facility_key, i.owner_key, i.parent_company_key)
    where {{ dbt.length('d.donor_key') }} >= 4

    union all

    select
        a.official_id,
        a.registry_id,
        db.donor_key,
        0 as by_name
    from areas as a
    inner join facility_brands as fb on a.registry_id = fb.registry_id
    inner join donor_brands as db on a.official_id = db.official_id and fb.brand = db.brand
),

matches as (
    -- one row per (official, facility, donor) before summing, so a donor matched both ways counts once
    select
        m.official_id,
        m.registry_id,
        max(m.by_name) as by_name,
        min(d.donor_name) as donor_name,
        min(d.amount) as amount,
        min(d.n_contributions) as n_contributions,
        min(d.first_year) as first_year,
        min(d.last_year) as last_year,
        min(d.source_url) as source_url,
        min(d.is_medium) as is_medium
    from matched_donors as m
    inner join donors as d on m.official_id = d.official_id and m.donor_key = d.donor_key
    group by m.official_id, m.registry_id, m.donor_key
),

per_facility as (
    select
        official_id,
        registry_id,
        case when max(by_name) = 1 then 'same name' else 'same company' end as matched_by,
        {{ dbt.listagg('donor_name', "'; '", 'order by donor_name') }} as donor_names,
        sum(amount) as donated_amount,
        sum(n_contributions) as n_contributions,
        min(first_year) as first_year,
        max(last_year) as last_year,
        min(source_url) as source_url,
        case when max(is_medium) = 1 then 'medium' else 'high' end as match_confidence
    from matches
    group by official_id, registry_id
)

select
    a.official_id,
    a.registry_id,
    a.district_id,
    f.facility_name,
    f.address,
    f.city,
    f.postal_code,
    f.owner_name,
    f.parent_company_name,
    f.naics_code,
    f.naics_description,
    m.registry_id is not null as is_donor,
    m.matched_by,
    m.donor_names,
    m.donated_amount,
    m.n_contributions,
    cast(m.first_year as {{ dbt.type_int() }}) as first_year,
    cast(m.last_year as {{ dbt.type_int() }}) as last_year,
    m.match_confidence,
    m.source_url as contributions_url,
    f.frs_url
from areas as a
inner join {{ ref('fct_district_facilities') }} as f
    on a.registry_id = f.registry_id and a.district_id = f.district_id
left join per_facility as m on a.official_id = m.official_id and a.registry_id = m.registry_id
