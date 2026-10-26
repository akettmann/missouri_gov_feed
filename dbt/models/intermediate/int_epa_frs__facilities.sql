-- EPA FRS facilities in Missouri that have coordinates, with one owner, one parent company and one primary
-- NAICS code each. The owner is the first owner-role organization (owner/operator, owner, operator,
-- permittee; a known org_type before UNKNOWN, then name, then org_type alphabetically (a stable key, not a
-- ranking of types), then program record, so tied names pick the same row every build, #386); the NAICS
-- code is the code the most program systems give (program_system: RCRAINFO, NPDES, AIR, ... each counts once
-- per code however many records it has, so a duplicated NPDES permit or an air record listed twice adds nothing;
-- AIR and AIRS/AFS are one program under two names (the same air permit, mirrored IDs) and count once; a
-- 4- or 5-digit code (RCRAINFO, EIS and RMP truncate: 81232) counts for the 6-digit code at the same facility
-- that extends it (812320), so the two forms of one code no longer split the vote, #432; a short code gives a full
-- vote to EVERY 6-digit code it extends, so two 6-digit codes sharing a 5-digit prefix both get that vote),
-- taking the programs'
-- primary codes first (naics_source 'naics'), then the ones FRS leaves UNKNOWN
-- ('naics_unknown'), then the ones it calls SECONDARY ('naics_secondary'). Only a facility with no NAICS code
-- at all but a SIC code (a primary one before an unknown or secondary one, then the one the most program systems give)
-- gets the NAICS sector that SIC code's major group falls in (seed sic_naics_sectors): naics_code is then the
-- two-digit sector prefix, naics_description names the sector and the SIC code, and naics_source is 'sic'.
-- naics_source is null when the facility has no usable code. A real NAICS code, even a non-primary one, is
-- more precise than a two-digit SIC-derived sector, and agrees with it on the sector for about 90% of facilities.
-- Codes tied on tier and program-system count: the one more program systems give across ALL tiers, not counting
-- MO-DNR and RMP (the same count over primary, unknown and secondary rows; the UNKNOWN-tier rows usually back the
-- right code, #432; MO-DNR is a state copy of what other systems report: at most facilities where another system also
-- reports a NAICS code, its code matches (or extends or truncates) one of theirs. RMP, the facility's own Risk
-- Management Plan, does so at only about half of those facilities, so it is not a pure mirror, but it is left out on
-- purpose:
-- counted, it would let one more UNKNOWN row outvote the SIC sector (#513,
-- #520); a judgment call, not a claim that RMP duplicates another system); then the one in the SIC-derived sector
-- (NAICS 31-33 count as one sector); then any other
-- code before the construction stormwater-permit noise code NAICS 238910 (a site holds that permit beside its real
-- industry, #432), which still wins when the SIC sector is construction; then the all-tier count again with MO-DNR
-- and RMP included (they still back a code when nothing else separates them), then a 6-digit code before a
-- shorter one, then the lowest code. The SIC sector counts only as a signal when the SIC code is not itself tied
-- (same tier and program-system count) with a SIC code in a different sector, and is not construction
-- stormwater-permit noise: SIC 1629, or 1541/1542/1611 given only by NPDES (or its MO-DNR copy), #513. A
-- 1541/1542/1611 given only by MO-DNR, with no NPDES row, is read as noise too (21 facility/code pairs), #520.
-- is_government: a federal site, any owner-role organization typed as a government body
-- (municipal, county, state, federal, district, tribal), or a facility or owner named like one ("City of ...",
-- "... County", "... School District"; most organizations are typed UNKNOWN). The *_key columns are
-- company_key names for matching donors.
{% set sic_description_parts = [
    "sec.sector_name", "' sector, from SIC '", "ps.sic_code", "' '", "ps.sic_description"
] %}
{# FRS lists one air program under two names; count it once. #}
{% set program_family = "case when program_system = 'AIRS/AFS' then 'AIR' else program_system end" %}
{% set government_name = (
    '(^| )(city|town|village|county|state) of | county$|county commission'
    ~ '|school district|water district|sewer district|public works'
) %}

with orgs as (
    select
        registry_id,
        org_name,
        org_type,
        program_system,
        program_id,
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
            order by
                owner_rank,
                case when coalesce(org_type, 'UNKNOWN') = 'UNKNOWN' then 1 else 0 end,
                org_name,
                -- same name on two owner rows (#386): a neutral stable key, not a ranking of types, so the pick
                -- no longer depends on row order. owner_type is the alphabetically first org_type, then the
                -- program record that carries it
                coalesce(org_type, ''),
                program_system,
                program_id
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
        row_number() over (partition by registry_id order by org_name, program_system, program_id) as rn
    from orgs
    where is_parent
),

sic as (
    select
        registry_id,
        sic_code,
        max(sic_description) as sic_description,
        min(case when is_primary then 0 when is_secondary then 2 else 1 end) as rank_class,
        count(distinct coalesce({{ program_family }}, '')) as n_program_systems,
        -- only NPDES (or its MO-DNR copy) gives the code: a stormwater permit's construction code (#513)
        coalesce(max(case when program_system not in ('NPDES', 'MO-DNR') then 1 else 0 end), 0) = 0 as npdes_only
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
        s.n_program_systems,
        s.npdes_only,
        m.naics_prefix,
        row_number()
            over (partition by s.registry_id, s.sic_code order by length(m.sic_prefix) desc, m.naics_prefix)
            as rn
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
        sp.n_program_systems,
        sp.npdes_only,
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
        -- SIC 1629, or a 1541/1542/1611 only NPDES gives, is the construction stormwater permit (#432, #513): it
        -- loses ties to a real industry and says nothing about the facility's sector
        (sic_code = '1629' or (sic_code in ('1541', '1542', '1611') and npdes_only)) as sic_is_permit_noise,
        -- SIC codes tied on tier and program-system count that fall in different sectors: the lowest-code tie-break
        -- picked the SIC code, so its sector is no evidence of the facility's industry (#181)
        (
            min(sector_code) over (partition by registry_id, rank_class, n_program_systems)
            != max(sector_code) over (partition by registry_id, rank_class, n_program_systems)
        ) as sic_is_tied_across_sectors,
        row_number() over (
            partition by registry_id
            order by
                rank_class asc,
                n_program_systems desc,
                -- SIC 1629 (the construction stormwater permit) loses ties to a real industry (#432), then the
                -- lowest code; other construction codes (1521, 1794, ...) are real industries and keep their place
                case
                    when sic_code = '1629' or (sic_code in ('1541', '1542', '1611') and npdes_only) then 1 else 0
                end asc,
                sic_code asc
        ) as rn
    from sic_sectors
),

naics_rows as (
    select
        registry_id,
        naics_code,
        naics_description,
        coalesce({{ program_family }}, '') as program_family,
        case when is_primary then 0 when is_secondary then 2 else 1 end as rank_class
    from {{ ref('stg_epa_frs__naics') }}
    where naics_code is not null
),

-- the 6-digit codes a facility has: the targets a shorter code at the same facility extends
naics_full as (
    select
        registry_id,
        naics_code,
        max(naics_description) as naics_description
    from naics_rows
    where length(naics_code) = 6
    group by registry_id, naics_code
),

-- a 4- or 5-digit code becomes (one row per) 6-digit code of the same facility it is the prefix of, and takes that
-- code's description; with no such code it stays as it is
naics_normalised as (
    select
        r.registry_id,
        coalesce(f.naics_code, r.naics_code) as naics_code,
        coalesce(f.naics_description, r.naics_description) as naics_description,
        r.program_family,
        r.rank_class
    from naics_rows as r
    left join naics_full as f
        on
            r.registry_id = f.registry_id
            and length(r.naics_code) < 6
            and left(f.naics_code, length(r.naics_code)) = r.naics_code
),

naics as (
    select
        registry_id,
        naics_code,
        max(naics_description) as naics_description,
        rank_class,
        count(distinct program_family) as n_program_systems
    from naics_normalised
    group by registry_id, naics_code, rank_class
),

-- program systems per code over every tier, a tie-break within a tier
naics_all_tiers as (
    select
        registry_id,
        naics_code,
        count(distinct program_family) as n_systems_all_tiers,
        -- the same count without MO-DNR (a state copy of other systems) and RMP (left out by choice, #520), #513
        count(distinct case when program_family not in ('MO-DNR', 'RMP') then program_family end)
            as n_independent_all_tiers
    from naics_normalised
    group by registry_id, naics_code
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
                n.n_program_systems desc,
                -- program systems over every tier, not counting MO-DNR (a copy of other systems) or RMP (left out by
                -- choice, #520): they must not outvote the SIC sector (#513)
                allt.n_independent_all_tiers desc,
                -- among tied codes, the one in the sector the facility's SIC code maps to (#181); no signal from
                -- a construction stormwater-permit SIC code or a SIC code tied across sectors
                case
                    when
                        not ps.sic_is_permit_noise
                        and not coalesce(ps.sic_is_tied_across_sectors, false)
                        and sc.sector_code = ps.sector_code
                        then 0
                    else 1
                end asc,
                -- 238910 (the construction stormwater permit) loses ties to a real industry (#432). Other
                -- construction codes are real industries
                case when n.naics_code = '238910' then 1 else 0 end asc,
                -- all systems, MO-DNR and RMP included: they still back a code when nothing else separates them
                allt.n_systems_all_tiers desc,
                -- a full 6-digit code before a truncated one, then the code order
                length(n.naics_code) desc,
                n.naics_code asc
        ) as rn
    from naics as n
    inner join naics_all_tiers as allt on n.registry_id = allt.registry_id and n.naics_code = allt.naics_code
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
