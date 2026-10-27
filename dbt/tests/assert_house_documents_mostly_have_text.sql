-- Sanity check: text coverage of the House documents the mo_house_pdf loader fetched. Fewer than 98% of a kind's
-- fetched PDFs with extracted text (at least 20 fetched) means the extraction broke (a PDF library change, an
-- image-only batch) rather than a few scans. 0 of 524 fetched PDFs in the 2018 and 2022-2025 special sessions
-- had no text layer.
select
    document_kind,
    count(*) as fetched,
    sum(case when has_text then 1 else 0 end) as with_text
from {{ ref('stg_mo_house__document_texts') }}
where fetch_error is null
group by document_kind
having count(*) >= 20 and sum(case when has_text then 1 else 0 end) < 0.98 * count(*)
