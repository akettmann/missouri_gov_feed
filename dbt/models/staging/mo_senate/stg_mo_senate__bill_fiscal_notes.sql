-- One row per fiscal-note PDF link on a Senate bill's page at senate.mo.gov, in the order the page lists them
-- (doc_index 0 first). label is the link text as printed ("Perfected (0453S.04P.ORG)"); the PDFs are not fetched
-- (#590). session_code is the House's code for the session (seed mo_senate_session_codes), null for a session with no
-- seed row. Text is cleaned with the shared macros; the url is trimmed only.
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
        {{ mogov.json_str('payload', '$.label') }} as label_raw
    from {{ source('mo_senate', 'bill_fiscal_notes') }}
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
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.label_raw')) }} as label
from src
left join {{ ref('mo_senate_session_codes') }} as codes
    on src.session_year = codes.session_year and src.session_type = codes.session_type
