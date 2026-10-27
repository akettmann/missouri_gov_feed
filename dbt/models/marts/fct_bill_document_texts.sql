-- The text of the House's bill documents, one row per document URL: bill text versions, summaries, fiscal notes and
-- amendments that the mo_house_pdf loader fetched (empty until that loader has run). Kept apart from
-- fct_bill_documents so the link mart stays small; the text is wide (the 2017-2026 set is a few GB of text). Join to
-- fct_bill_documents on document_url for the bill, version label and index: a summary shared by several versions
-- is one row here and one row per bill in fct_bill_documents. document_text has control characters removed.
-- Documents with a fetch_error have no text. A scanned page has no text layer: it adds to page_count but not to
-- the text.
select
    document_url,
    document_kind,
    session_code,
    lr_number,
    version_code,
    n_links,
    page_count,
    text_length,
    has_text,
    fetch_error,
    document_text
from {{ ref('stg_mo_house__document_texts') }}
