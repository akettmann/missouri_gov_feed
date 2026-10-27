-- One row per bill text version (PDF link) on a Senate bill's page at senate.mo.gov, in the order the page lists them
-- (doc_index 0 first). The PDFs themselves are not fetched (#590). label is the link text as printed
-- ("0453S.04T - Truly Agreed to and Finally Passed"), lr_number and version its two halves (version is the whole label
-- when the text has no " - "). session_code is the House's code for the session (seed mo_senate_session_codes), null
-- for a session with no seed row. Text is cleaned with the shared macros (whitespace, entities, U+FFFD); the url is
-- trimmed only.
{%- set year_expr -%}
coalesce(
    {{ mogov.json_str('payload', '$.list_year') }},
    {{ mogov.json_str('payload', '$.year') }}
)
{%- endset %}
with src as (
    select
        {{ dbt.safe_cast(year_expr, dbt.type_int()) }} as session_year,
        {{ mogov.json_str('payload', '$.session_type') }} as session_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.bill_id'), dbt.type_int()) }} as bill_id,
        {{ mogov.json_str('payload', '$.bill') }} as bill,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.doc_index'), dbt.type_int()) }} as doc_index,
        trim({{ mogov.json_str('payload', '$.url') }}) as document_url,
        {{ mogov.json_str('payload', '$.title') }} as title_raw,
        {{ mogov.json_str('payload', '$.label') }} as label_raw,
        {{ mogov.json_str('payload', '$.lr_number') }} as lr_number_raw,
        {{ mogov.json_str('payload', '$.version') }} as version_raw
    from {{ source('mo_senate', 'bill_texts') }}
)

select
    src.session_year,
    src.session_type,
    codes.house_session_code as session_code,
    src.bill_id,
    src.bill,
    src.doc_index,
    src.document_url,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.title_raw')) }} as title,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.label_raw')) }} as label,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.lr_number_raw')) }} as lr_number,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.version_raw')) }} as version
from src
left join {{ ref('mo_senate_session_codes') }} as codes
    on src.session_year = codes.session_year and src.session_type = codes.session_type
