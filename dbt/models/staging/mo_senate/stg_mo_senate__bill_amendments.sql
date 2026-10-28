-- One row per amendment PDF link on a Senate bill's page at senate.mo.gov, in the order the page lists them
-- (doc_index 0 first). label is the link text as printed ("2/4/2025 - SS S offered & adopted (Crawford)--(0453S.04F)"),
-- status the chip beside it ("2/4/2025 - Adopted"; null when the page shows none), amendment_id the site's own key
-- from the PDF url. The PDFs are not fetched (#590). session_code is the House's code for the session (seed
-- mo_senate_session_codes), null for a session with no seed row. Text is cleaned with the shared macros; the url is
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
        {{ dbt.safe_cast(mogov.json_str('payload', '$.amendment_id'), dbt.type_bigint()) }} as amendment_id,
        trim({{ mogov.json_str('payload', '$.url') }}) as document_url,
        {{ mogov.json_str('payload', '$.title') }} as title_raw,
        {{ mogov.json_str('payload', '$.label') }} as label_raw,
        {{ mogov.json_str('payload', '$.status') }} as status_raw
    from {{ source('mo_senate', 'bill_amendments') }}
)

select
    src.session_year,
    src.session_type,
    codes.house_session_code as session_code,
    src.bill_id,
    src.bill,
    src.doc_index,
    src.amendment_id,
    src.document_url,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.title_raw')) }} as title,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.label_raw')) }} as label,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.status_raw')) }} as status
from src
left join {{ ref('mo_senate_session_codes') }} as codes
    on src.session_year = codes.session_year and src.session_type = codes.session_type
