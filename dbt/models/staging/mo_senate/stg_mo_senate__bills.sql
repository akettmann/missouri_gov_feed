-- One row per Senate bill or resolution (SB, SJR, SCR, SR) in senate.mo.gov's bill list, for the sessions the
-- mo_senate_bills loader has landed (regular and extraordinary). The list is complete: it does not depend on the
-- bill having a topical-index keyword or reaching the House. session_code is the House's code for the session
-- (seed mo_senate_session_codes), null for a session with no seed row (a test fails on that). bill_id is the
-- site's own key, not the bill number. Resolutions have no handler. bill_type is the prefix (SB, SJR, SCR, SR, ...).
-- legislator_id is the sponsor's id in the list's `legislatorId` (the site's own legislator key, not the House's).
-- session_year is read from `list_year` when the loader wrote one (the year of the list the bill came from), else
-- from the served `year` key: the loader used to overwrite the served `year` with the list's year, and they agree.
{%- set coalesce_json_year -%}
coalesce(
    {{ mogov.json_str('payload', '$.list_year') }},
    {{ mogov.json_str('payload', '$.year') }}
)
{%- endset %}
with src as (
    select
        {{ dbt.safe_cast(coalesce_json_year, dbt.type_int()) }} as session_year,
        {{ mogov.json_str('payload', '$.session_type') }} as session_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.billId'), dbt.type_int()) }} as bill_id,
        {{ mogov.json_str('payload', '$.billPrefix') }} as bill_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.legislatorId'), dbt.type_int()) }} as legislator_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.billSuffix'), dbt.type_int()) }} as bill_number,
        {{ mogov.json_str('payload', '$.briefDescription') }} as short_title,
        {{ mogov.json_str('payload', '$.sponsorLastName') }} as sponsor_last_name,
        {{ mogov.json_str('payload', '$.sponsorFirstName') }} as sponsor_first_name,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.districtNumber'), dbt.type_int()) }} as sponsor_district,
        {{ mogov.json_str('payload', '$.handlerLastName') }} as handler_last_name,
        {{ mogov.json_str('payload', '$.handlerFirstName') }} as handler_first_name,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.handlerDistrict'), dbt.type_int()) }} as handler_district,
        {{ mogov.json_str('payload', '$.mainBillUrl') }} as bill_url
    from {{ source('mo_senate', 'bill_list') }}
)

select
    src.session_year,
    src.session_type,
    codes.house_session_code as session_code,
    src.bill_id,
    src.bill_type || cast(src.bill_number as {{ dbt.type_string() }}) as bill,
    src.bill_type,
    src.bill_number,
    src.short_title,
    src.sponsor_last_name || ', ' || src.sponsor_first_name as sponsor_name,
    src.legislator_id,
    src.sponsor_district,
    src.handler_last_name || ', ' || src.handler_first_name as handler_name,
    src.handler_district,
    src.bill_url
from src
left join {{ ref('mo_senate_session_codes') }} as codes
    on src.session_year = codes.session_year and src.session_type = codes.session_type
