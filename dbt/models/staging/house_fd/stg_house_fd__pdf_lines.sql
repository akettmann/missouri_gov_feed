-- U.S. House disclosure PDF text, one row per extracted line (Missouri filers); scanned filings appear once
-- with has_text = false. A PDF the loader could not download or extract (fetch error, extraction timeout) lands as one
-- row with load_error set and no has_text/page/line (#714).
select
    {{ mogov.json_str('payload', '$.doc_id') }} as doc_id,
    {{ mogov.json_str('payload', '$.url') }} as document_url,
    {{ mogov.json_str('payload', '$.has_text') }} = 'true' as has_text,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.page'), dbt.type_int()) }} as page,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.line_no'), dbt.type_int()) }} as line_no,
    {{ mogov.json_str('payload', '$.text') }} as line_text,
    {{ mogov.json_str('payload', '$.error') }} as load_error
from {{ source('house_fd', 'pdf_lines') }}
