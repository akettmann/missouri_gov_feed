-- One row per bill summary on a Senate bill's page at senate.mo.gov, in the order the page lists them (doc_index 0
-- first). A summary has no PDF: the page prints its text, which lands as served (summary_text keeps its line breaks and
-- tabs). label is the version heading ("Introduced"). summary_id is the site's own key. With no link, a summary is not
-- a row of fct_bill_documents (document_url is part of its grain). session_code is the House's code for the session
-- (seed mo_senate_session_codes), null for a session with no seed row. label is cleaned with the shared macros;
-- summary_text is left as printed apart from U+FFFD (it is prose, and whitespace is its layout).
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
        {{ dbt.safe_cast(mogov.json_str('payload', '$.summary_id'), dbt.type_bigint()) }} as summary_id,
        {{ mogov.json_str('payload', '$.label') }} as label_raw,
        {{ mogov.json_str('payload', '$.text') }} as text_raw
    from {{ source('mo_senate', 'bill_summaries') }}
)

select
    src.session_year,
    src.session_type,
    codes.house_session_code as session_code,
    src.bill_id,
    src.bill,
    src.doc_index,
    src.summary_id,
    {{ mogov.clean_registry_text(mogov.fix_replacement_char('src.label_raw')) }} as label,
    {{ mogov.fix_replacement_char('src.text_raw') }} as summary_text
from src
left join {{ ref('mo_senate_session_codes') }} as codes
    on src.session_year = codes.session_year and src.session_type = codes.session_type
