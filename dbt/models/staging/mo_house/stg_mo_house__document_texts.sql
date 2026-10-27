-- The text of the House's bill documents (bill text versions, summaries, fiscal notes, amendments) that the
-- mo_house_pdf loader fetched: one row per document URL, with the NUL and other control characters removed from
-- the text (see clean_pdf_text). A document that failed to download or extract has a row with fetch_error set and
-- no text; the loader retries it on its next run. A summary shared by several bill versions is one row (n_links
-- counts the links). bill is the House bill whose XML first names the URL; it is null when the first link is on a
-- Senate bill listed in the SenateActList (that list's file holds many bills), so join to fct_bill_documents on
-- document_url for the bill. The state row in mo_house_pdf_files adds the HTTP status and the file's size.
with cleaned as (
    select
        trim(t.url) as document_url,
        t.kind as document_kind,
        t.session_code,
        t.file_name,
        t.lr_number,
        t.version_code,
        t.n_links,
        t.page_count,
        {{ mogov.clean_pdf_text('t.text') }} as document_text,
        t.error as fetch_error,
        f.http_status,
        f.size_bytes
    from {{ source('mo_house', 'pdf_texts') }} as t
    left join {{ source('mo_house', 'pdf_files') }} as f
        on trim(t.url) = trim(f.url)
)

select
    c.document_url,
    c.document_kind,
    c.session_code,
    b.bill,
    c.lr_number,
    c.version_code,
    c.n_links,
    c.page_count,
    c.document_text,
    coalesce(length(c.document_text), 0) as text_length,
    coalesce({{ mogov.regex_matches('c.document_text', '\\S') }}, false) as has_text,
    c.fetch_error,
    c.http_status,
    c.size_bytes
from cleaned as c
left join {{ source('mo_house', 'xml_bills') }} as b
    on c.session_code = b.session_code and c.file_name = b.file_name
