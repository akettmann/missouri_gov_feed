-- EPA FRS facilities in Missouri that have coordinates, with one owner, one parent company and one primary
-- NAICS code each. The owner is the first owner-role organization (owner/operator, owner, operator,
-- permittee; a known org_type before UNKNOWN); the NAICS code is the primary code most of the facility's
-- programs give. is_government: a federal site, any owner-role organization typed as a government body
-- (municipal, county, state, federal, district, tribal), or a facility or owner named like one ("City of ...",
-- "... County", "... School District"; most organizations are typed UNKNOWN). The *_key columns are
-- company_key names for matching donors.
{% set government_name = (
    '(^| )(city|town|village|county|state) of | county$|county commission'
    ~ '|school district|water district|sewer district|public works'
) %}

with orgs as (
    select
        registry_id,
        org_name,
        org_type,
        case
            when affiliation_type = 'OWNER/OPERATOR' then 1
            when affiliation_type = 'OWNER' then 2
            when affiliation_type = 'OPERATOR' then 3
            when affiliation_type in ('PERMITEE', 'PERMITTEE') then 4
        end as owner_rank,
        affiliation_type in (
            'PARENT COMPANY', 'PARENT COMPANY 1', 'PARENT COMPANY 2', 'PARENT OWNER', 'JOINT PARENT COMPANY'
        ) as is_parent
    from {{ ref('stg_epa_frs__organizations') }}
    where
        nullif(trim(org_name), '') is not null
        and upper(trim(org_name)) not in ('NA', 'N/A', 'UNKNOWN', 'NONE')
),

owners as (
    select
        registry_id,
        org_name as owner_name,
        org_type as owner_type,
        row_number() over (
            partition by registry_id
            order by owner_rank, case when coalesce(org_type, 'UNKNOWN') = 'UNKNOWN' then 1 else 0 end, org_name
        ) as rn
    from orgs
    where owner_rank is not null
),

government as (
    select distinct registry_id
    from orgs
    where
        owner_rank is not null
        and org_type in ('MUNICIPAL', 'COUNTY', 'STATE', 'FEDERAL', 'DISTRICT', 'PUBLIC', 'GOVERNMENT', 'TRIBE')
),

parents as (
    select
        registry_id,
        org_name as parent_company_name,
        row_number() over (partition by registry_id order by org_name) as rn
    from orgs
    where is_parent
),

naics as (
    select
        registry_id,
        naics_code,
        max(naics_description) as naics_description,
        count(*) as n_programs
    from {{ ref('stg_epa_frs__naics') }}
    where is_primary
    group by registry_id, naics_code
),

primary_naics as (
    select
        registry_id,
        naics_code,
        naics_description,
        row_number() over (partition by registry_id order by n_programs desc, naics_code asc) as rn
    from naics
)

select
    f.registry_id,
    f.facility_name,
    f.address,
    f.city,
    f.county,
    f.postal_code,
    f.latitude,
    f.longitude,
    o.owner_name,
    o.owner_type,
    p.parent_company_name,
    n.naics_code,
    n.naics_description,
    (
        f.federal_agency_name is not null
        or g.registry_id is not null
        or coalesce({{ mogov.regex_matches(mogov.name_key('f.facility_name'), government_name) }}, false)
        or coalesce({{ mogov.regex_matches(mogov.name_key('o.owner_name'), government_name) }}, false)
    ) as is_government,
    {{ mogov.company_key('f.facility_name') }} as facility_key,
    {{ mogov.company_key('o.owner_name') }} as owner_key,
    {{ mogov.company_key('p.parent_company_name') }} as parent_company_key,
    f.frs_url
from {{ ref('stg_epa_frs__facilities') }} as f
left join owners as o on f.registry_id = o.registry_id and o.rn = 1
left join parents as p on f.registry_id = p.registry_id and p.rn = 1
left join primary_naics as n on f.registry_id = n.registry_id and n.rn = 1
left join government as g on f.registry_id = g.registry_id
where f.latitude is not null and f.longitude is not null
