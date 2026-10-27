-- A disclosure PDF the loader could not download or extract (fetch error, extraction timeout) lands as an error row
-- and its filing shows in fct_disclosures as "download or text extraction failed". A handful is a flaky day (the next
-- run retries them); more than 10 documents means the Clerk's site changed or blocks us, or the extractor is
-- timing out on everything. Warns, so a bad day does not stop the build (#714).
{{ config(severity='warn') }}

select count(distinct doc_id) as documents_with_load_errors
from {{ ref('stg_house_fd__pdf_lines') }}
where load_error is not null
having count(distinct doc_id) > 10
