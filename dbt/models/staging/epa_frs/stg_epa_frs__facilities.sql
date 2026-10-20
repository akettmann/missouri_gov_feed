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
)

select
    registry_id,
    facility_name,
    nullif(address, '') as address,
    nullif(city, '') as city,
    nullif(county, '') as county,
    nullif(county_fips, '') as county_fips,
    nullif(postal_code, '') as postal_code,
    nullif(site_type, '') as site_type,
    nullif(federal_agency_name, '') as federal_agency_name,
    program_systems,
    {{ dbt.safe_cast("nullif(latitude_text, '')", dbt.type_float()) }} as latitude,
    {{ dbt.safe_cast("nullif(longitude_text, '')", dbt.type_float()) }} as longitude,
    frs_url,
    source_url
from src
where registry_id is not null
