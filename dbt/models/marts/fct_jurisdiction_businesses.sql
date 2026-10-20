-- Businesses operating in each district-elected official's area: the non-government EPA-regulated facilities
-- (EPA FRS) in the district a legislator or U.S. representative is elected from, or a mayor's city, and whether
-- the official received campaign contributions from them. Judges are left out (a circuit or federal district
-- holds thousands of sites and judges take almost no organization money), as are statewide offices. A
-- contribution counts when the donor organization's company_key equals the facility's, its owner's or its
-- parent company's ("Ameren Missouri" gives to an official whose district holds an Ameren Missouri plant).
-- Exact names only: a donor writing its name differently is missed, and donor keys under four characters are
-- not matched.
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
        count(*) as n_contributions
    from {{ ref('fct_campaign_finance') }}
    where
        direction = 'received'
        and lower(coalesce(counterparty_type, '')) <> 'individual'
        and amount > 0
    group by
        official_id,
        {{ mogov.company_key("coalesce(nullif(trim(counterparty_organization), ''), counterparty)") }}
),

matches as (
    select
        a.official_id,
        a.registry_id,
        min(d.donor_name) as donor_name,
        sum(d.amount) as donated_amount,
        sum(d.n_contributions) as n_contributions
    from areas as a
    inner join {{ ref('int_epa_frs__facilities') }} as i on a.registry_id = i.registry_id
    inner join donors as d
        on
            a.official_id = d.official_id
            and d.donor_key in (i.facility_key, i.owner_key, i.parent_company_key)
    where {{ dbt.length('d.donor_key') }} >= 4
    group by a.official_id, a.registry_id
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
    m.donor_name,
    m.donated_amount,
    m.n_contributions,
    f.frs_url
from areas as a
inner join {{ ref('fct_district_facilities') }} as f
    on a.registry_id = f.registry_id and a.district_id = f.district_id
left join matches as m on a.official_id = m.official_id and a.registry_id = m.registry_id
