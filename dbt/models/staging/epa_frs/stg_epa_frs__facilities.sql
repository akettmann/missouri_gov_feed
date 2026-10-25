-- One row per EPA FRS facility in Missouri: name, street address, county, coordinates (NAD83; missing for about
-- a third of the sites) and the federal agency for federal sites. Malformed CSV rows (no REGISTRY_ID) are left
-- out.
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
)

select
    src.registry_id,
    {{ mogov.fix_replacement_char('src.facility_name', 'fixes.corrected_value') }} as facility_name,
    nullif(trim({{ mogov.fix_replacement_char('src.address') }}), '') as address,
    nullif(src.city, '') as city,
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
where src.registry_id is not null
