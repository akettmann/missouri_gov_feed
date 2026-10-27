-- Sanity check on the House disclosure PDF parser: in every year, nearly all of the annual and candidate report PDFs
-- with extractable text yield schedule lines (extension requests, threshold notices, amendments and the other
-- filing types in financial-pdfs/ are short forms with no schedules, so they are left out: #599).
-- When the parser stops recognizing a year's schedule headers, its reports
-- silently fall back to a single "not text-extractable" row: it happened for every report from 2022 on (and 8 of
-- the 25 from 2021) when the PDFs began extracting their small-caps headers as NUL characters (#576).
-- A header-only report (every schedule "None disclosed.", nothing but form boilerplate: 9 of them today) yields
-- no lines legitimately. It is recognized from the raw lines alone, never from the model or its restore macro,
-- so a parser regression cannot excuse itself: at least 6 "None disclosed." lines (one per schedule on the form),
-- and, once those lines and the header above each are set aside, no more than 30 lines remain (the form's front
-- matter and closing pages are about 23).
-- Returns one row per year where fewer than 90% of the text PDFs produce a schedule line or are header-only.
with docs as (
    select
        doc_id,
        {{ mogov.regex_extract('document_url', '/financial-pdfs/([0-9]{4})/') }} as filing_year,
        count(*) as line_count,
        sum(case when lower(line_text) in ('none disclosed.', 'none disclosed') then 1 else 0 end) as none_lines
    from {{ ref('stg_house_fd__pdf_lines') }}
    where
        has_text
        and document_url like '%/financial-pdfs/%'
        and doc_id in (
            select f.doc_id
            from {{ ref('stg_house_fd__filings') }} as f
            where f.filing_kind in ('annual report', 'candidate report')
        )
    group by doc_id, document_url
),

parsed as (
    select distinct doc_id from {{ ref('int_house_fd__schedule_lines') }}
)

select
    d.filing_year,
    count(*) as text_documents,
    count(p.doc_id)
    + sum(case when p.doc_id is null and d.none_lines >= 6 and d.line_count - 2 * d.none_lines <= 30 then 1 else 0 end)
        as documents_parsed_or_header_only
from docs as d
left join parsed as p on d.doc_id = p.doc_id
group by d.filing_year
having
    count(p.doc_id)
    + sum(case when p.doc_id is null and d.none_lines >= 6 and d.line_count - 2 * d.none_lines <= 30 then 1 else 0 end)
    < 0.9 * count(*)
