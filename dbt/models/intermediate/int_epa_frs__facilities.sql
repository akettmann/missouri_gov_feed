-- EPA FRS facilities in Missouri that have coordinates, with one owner, one parent company and one primary
-- NAICS code each. The owner is the first owner-role organization (owner/operator, owner, operator,
-- permittee; a known org_type before UNKNOWN); the NAICS code is the code most of the facility's programs give,
-- taking the programs' primary codes first (naics_source 'naics'), then the ones FRS leaves UNKNOWN
-- ('naics_unknown'), then the ones it calls SECONDARY ('naics_secondary'). Only a facility with no NAICS code
-- at all but a SIC code (a primary one before an unknown or secondary one, then the one most programs give)
-- gets the NAICS sector that SIC code's major group falls in (seed sic_naics_sectors): naics_code is then the
-- two-digit sector prefix, naics_description names the sector and the SIC code, and naics_source is 'sic'.
-- naics_source is null when the facility has no usable code. A real NAICS code, even a non-primary one, is
-- more precise than a two-digit SIC-derived sector, and agrees with it on the sector for about 90% of facilities.
-- Codes tied on tier and program count go to the one in the SIC-derived sector (NAICS 31-33 count as one
-- sector), then the lowest code. The SIC sector counts only as a signal when the SIC code is not itself tied
-- (same tier and program count) with a SIC code in a different sector, and is not SIC 1629 (construction
-- stormwater-permit noise).
-- is_government: a federal site, any owner-role organization typed as a government body
-- (municipal, county, state, federal, district, tribal), or a facility or owner named like one ("City of ...",
-- "... County", "... School District"; most organizations are typed UNKNOWN). The *_key columns are
-- company_key names for matching donors.
{% set sic_description_parts = [
    "sec.sector_name", "' sector, from SIC '", "ps.sic_code", "' '", "ps.sic_description"
] %}
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

sic as (
    select
        registry_id,
        sic_code,
        max(sic_description) as sic_description,
        min(case when is_primary then 0 when is_secondary then 2 else 1 end) as rank_class,
        count(*) as n_programs
    from {{ ref('stg_epa_frs__sic') }}
    where sic_code is not null
    group by registry_id, sic_code
),

sic_prefixes as (
    select
        s.registry_id,
        s.sic_code,
        s.sic_description,
        s.rank_class,
        s.n_programs,
        m.naics_prefix,
        row_number() over (partition by s.registry_id, s.sic_code order by length(m.sic_prefix) desc) as rn
    from sic as s
    inner join {{ ref('sic_naics_sectors') }} as m on left(s.sic_code, length(m.sic_prefix)) = m.sic_prefix
),

sic_sectors as (
    select
        sp.registry_id,
        sp.sic_code,
        sp.sic_description,
        sp.naics_prefix,
        sp.rank_class,
        sp.n_programs,
        sec.sector_code
    from sic_prefixes as sp
    left join {{ ref('naics_sectors') }} as sec on sp.naics_prefix = sec.naics_prefix
    where sp.rn = 1
),

primary_sic as (
    select
        registry_id,
        sic_code,
        sic_description,
        naics_prefix,
        sector_code,
        -- SIC codes tied on tier and program count that fall in different sectors: the lowest-code tie-break
        -- picked the SIC code, so its sector is no evidence of the facility's industry (#181)
        (
            min(sector_code) over (partition by registry_id, rank_class, n_programs)
            != max(sector_code) over (partition by registry_id, rank_class, n_programs)
        ) as sic_is_tied_across_sectors,
        row_number() over (partition by registry_id order by rank_class asc, n_programs desc, sic_code asc) as rn
    from sic_sectors
),

naics as (
    select
        registry_id,
        naics_code,
        max(naics_description) as naics_description,
        case when is_primary then 0 when is_secondary then 2 else 1 end as rank_class,
        count(*) as n_programs
    from {{ ref('stg_epa_frs__naics') }}
    where naics_code is not null
    group by registry_id, naics_code, case when is_primary then 0 when is_secondary then 2 else 1 end
),

best_naics as (
    select
        n.registry_id,
        n.naics_code,
        n.naics_description,
        n.rank_class,
        row_number() over (
            partition by n.registry_id
            order by
                n.rank_class asc,
                n.n_programs desc,
                -- among tied codes, the one in the sector the facility's SIC code maps to (#181); no signal from
                -- SIC 1629 (construction stormwater-permit noise) or a SIC code tied across sectors
                case
                    when
                        ps.sic_code != '1629'
                        and not ps.sic_is_tied_across_sectors
                        and sc.sector_code = ps.sector_code
                        then 0
                    else 1
                end asc,
                n.naics_code asc
        ) as rn
    from naics as n
    left join primary_sic as ps on n.registry_id = ps.registry_id and ps.rn = 1
    left join {{ ref('naics_sectors') }} as sc on left(n.naics_code, 2) = sc.naics_prefix
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
    coalesce(n.naics_code, ps.naics_prefix) as naics_code,
    coalesce(
        n.naics_description,
        case
            when ps.naics_prefix is not null
                then
                    {{ dbt.concat(sic_description_parts) }}
        end
    ) as naics_description,
    case
        when n.rank_class = 0 then 'naics'
        when n.rank_class = 1 then 'naics_unknown'
        when n.rank_class = 2 then 'naics_secondary'
        when ps.naics_prefix is not null then 'sic'
    end as naics_source,
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
left join best_naics as n on f.registry_id = n.registry_id and n.rn = 1
left join primary_sic as ps on f.registry_id = ps.registry_id and ps.rn = 1 and n.naics_code is null
left join {{ ref('naics_sectors') }} as sec on ps.naics_prefix = sec.naics_prefix
left join government as g on f.registry_id = g.registry_id
where f.latitude is not null and f.longitude is not null
