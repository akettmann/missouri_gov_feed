-- Sanity check: the documents the mo_house_pdf loader could not get, other than the known kinds. Known: a summary
-- link that answers 200 with an HTML error page ("not a PDF"; resolution and bill summaries such as
-- sumpdf/HR0001I.pdf, bills173/sumpdf/HB0001T.pdf)
-- and the two 2018 fiscal-note links on www.moga.mo.gov (HTML). Anything else (HTTP errors, timeouts) is
-- retried on the loader's next run, so a few are fine: this fails when more than 1% of a kind's landed documents
-- (at least 5 documents) are unexplained failures, which means the host changed or blocked the loader.
with landed as (
    select
        document_kind,
        count(*) as documents,
        sum(case
            when fetch_error is null then 0
            when document_kind = 'summary' and fetch_error = 'not a PDF' then 0
            when document_url like '%://www.moga.mo.gov/%' then 0
            else 1
        end) as unexplained
    from {{ ref('stg_mo_house__document_texts') }}
    group by document_kind
)

select
    document_kind,
    documents,
    unexplained
from landed
where unexplained >= 5 and unexplained > 0.01 * documents
