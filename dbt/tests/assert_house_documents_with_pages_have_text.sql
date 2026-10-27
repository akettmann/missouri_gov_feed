{{ config(warn_if='>0', error_if='>50') }}
-- Sanity check: a fetched PDF with pages but no text, which is a scan with no text layer (or a font the extractor
-- cannot read). A few are expected over the full 68.7k set, so this warns, and fails past 50. Each listed
-- document would need OCR to be searchable.
select
    document_url,
    document_kind,
    page_count
from {{ ref('stg_mo_house__document_texts') }}
where fetch_error is null and page_count > 0 and not has_text
