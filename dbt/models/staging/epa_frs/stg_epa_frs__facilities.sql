-- One row per EPA FRS facility in Missouri: name, street address, county, coordinates (NAD83; missing for about
-- a third of the sites) and the federal agency for federal sites. Malformed CSV rows (no REGISTRY_ID) are left
-- out. A name that still has U+FFFD (EPA lost a letter) is taken from the epa_frs_name_corrections seed if it has a
-- row, else from the one alternative name of the same registry id that equals it with each run of U+FFFD standing
-- for one character; failing both, the U+FFFD is dropped. Name, address and city have runs of whitespace
-- collapsed and stray leading/trailing commas, semicolons and spaces cut (EPA writes "BUTTERBALL,", #319); the HTML
-- entities EPA leaves in them (&AMP; &#39; &#40; &#41;) are decoded (#398).
with src as (
    select
        {{ mogov.json_str('payload', '$.REGISTRY_ID') }} as registry_id,
        {{ mogov.json_str('payload', '$.PRIMARY_NAME') }} as facility_name,
        {{ mogov.json_str('payload', '$.LOCATION_ADDRESS') }} as address,
        {{ mogov.json_str('payload', '$.CITY_NAME') }} as city,
        {{ mogov.json_str('payload', '$.COUNTY_NAME') }} as county,
        {{ mogov.json_str('payload', '$.FIPS_CODE') }} as county_fips,
        {{ mogov.json_str('payload', '$.POSTAL_CODE') }} as postal_code,
        {{ mogov.json_str('payload', '$.SITE_TYPE_NAME') }} as site_type,
        {{ mogov.json_str('payload', '$.FEDERAL_AGENCY_NAME') }} as federal_agency_name,
        {{ mogov.json_str('payload', '$.PGM_SYS_ACRNMS') }} as program_systems,
        {{ mogov.json_str('payload', '$.LATITUDE83') }} as latitude_text,
        {{ mogov.json_str('payload', '$.LONGITUDE83') }} as longitude_text,
        {{ mogov.json_str('payload', '$.FRS_FACILITY_DETAIL_REPORT_URL') }} as frs_url,
        source_url
    from {{ source('epa_frs', 'facilities') }}
),

fixes as (
    select
        record_key,
        corrected_value
    from {{ ref('epa_frs_name_corrections') }}
    where field = 'facility_name'
),

-- one alternative name matches the damaged pattern; two different matches are ambiguous and repair nothing
alt_repairs as (
    select
        src.registry_id,
        src.facility_name,
        min(alt.alt_name) as repaired_name
    from src
    inner join {{ ref('stg_epa_frs__alt_names') }} as alt on src.registry_id = alt.registry_id
    where
        src.facility_name like '%�%'
        and alt.alt_name not like '%�%'
        and alt.alt_name like {{ mogov.damaged_name_pattern('src.facility_name') }} escape '!'
    group by src.registry_id, src.facility_name
    having count(distinct alt.alt_name) = 1
)

select
    src.registry_id,
    {{ mogov.clean_registry_text(
        mogov.fix_replacement_char('src.facility_name', 'coalesce(fixes.corrected_value, alt_repairs.repaired_name)')
    ) }} as facility_name,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.address')) }} as address,
    {{ mogov.clean_registry_text('src.city') }} as city,
    nullif(src.county, '') as county,
    nullif(src.county_fips, '') as county_fips,
    nullif(src.postal_code, '') as postal_code,
    nullif(src.site_type, '') as site_type,
    nullif(src.federal_agency_name, '') as federal_agency_name,
    src.program_systems,
    {{ dbt.safe_cast("nullif(src.latitude_text, '')", dbt.type_float()) }} as latitude,
    {{ dbt.safe_cast("nullif(src.longitude_text, '')", dbt.type_float()) }} as longitude,
    src.frs_url,
    src.source_url
from src
left join fixes on src.registry_id = fixes.record_key
left join alt_repairs
    on src.registry_id = alt_repairs.registry_id and src.facility_name = alt_repairs.facility_name
where src.registry_id is not null
