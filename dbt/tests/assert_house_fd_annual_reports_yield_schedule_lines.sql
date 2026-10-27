-- Sanity check on the House disclosure PDF parser: in every year, nearly all of the annual-report PDFs with
-- extractable text yield schedule lines. When the parser stops recognizing a year's schedule headers, its reports
-- silently fall back to a single "not text-extractable" row: it happened for every report from 2022 on (and 8 of
-- the 25 from 2021) when the PDFs began extracting their small-caps headers as NUL characters (#576).
-- A report with no entries at all (every schedule "None disclosed.", only form boilerplate left) yields no lines
-- but still counts as parsed: its schedule headers were recognized.
-- Returns one row per year where fewer than 90% of the text PDFs produce a schedule line.
with docs as (
    select
        doc_id,
        {{ mogov.regex_extract('document_url', '/financial-pdfs/([0-9]{4})/') }} as filing_year
    from {{ ref('stg_house_fd__pdf_lines') }}
    where has_text and document_url like '%/financial-pdfs/%'
    group by doc_id, document_url
),

parsed as (
    select distinct doc_id from {{ ref('int_house_fd__schedule_lines') }}
    union
    select doc_id
    from (
        select
            doc_id,
            lower({{ mogov.house_fd_restore_text('line_text') }}) as line_text
        from {{ ref('stg_house_fd__pdf_lines') }}
        where has_text
    ) as restored
    where line_text like 'schedule _:%' or line_text like 'schedule a and b%' or line_text like 'schedule a %details'
    group by doc_id
)

select
    d.filing_year,
    count(*) as text_documents,
    count(p.doc_id) as documents_with_schedule_lines
from docs as d
left join parsed as p on d.doc_id = p.doc_id
group by d.filing_year
having count(p.doc_id) < 0.9 * count(*)
