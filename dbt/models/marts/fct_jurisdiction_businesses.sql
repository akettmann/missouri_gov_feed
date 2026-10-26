-- Businesses operating in each district-elected official's area: the non-government EPA-regulated facilities
-- (EPA FRS) in the district a legislator or U.S. representative is elected from, or a mayor's city, and whether
-- the official received campaign contributions from them. Judges are left out (a circuit or federal district
-- holds thousands of sites and judges take almost no organization money), as are statewide offices.
-- A donor organization matches a facility two ways:
--   same name     its company_key equals the facility's, its owner's or its parent company's (keys under four
--                 characters are not matched)
--   same company  the donor's name and the facility's, owner's or parent's name share a brand from the
--                 company_brands seed ("Ameren Missouri PAC" and a "UNION ELECTRIC CO" substation are Ameren)
-- The matching is int_jurisdiction_business_donor_matches; the donors themselves, with their filing pages, are
-- fct_jurisdiction_business_donors (one row per donor and page).
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

per_facility as (
    select
        official_id,
        registry_id,
        case when max(by_name) = 1 then 'same name' else 'same company' end as matched_by,
        sum(amount) as donated_amount,
        sum(n_contributions) as n_contributions,
        min(first_year) as first_year,
        max(last_year) as last_year,
        case when max(is_medium) = 1 then 'medium' else 'high' end as match_confidence
    from {{ ref('int_jurisdiction_business_donor_matches') }}
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
    m.donated_amount,
    m.n_contributions,
    cast(m.first_year as {{ dbt.type_int() }}) as first_year,
    cast(m.last_year as {{ dbt.type_int() }}) as last_year,
    m.match_confidence,
    f.frs_url
from areas as a
inner join {{ ref('fct_district_facilities') }} as f
    on a.registry_id = f.registry_id and a.district_id = f.district_id
left join per_facility as m on a.official_id = m.official_id and a.registry_id = m.registry_id
