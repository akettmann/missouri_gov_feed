-- The "Period Covered: 01/01/2016-11/11/2017" line on page 1 of a House disclosure PDF. Candidate reports and
-- their amendments carry it; annual reports do not. It is the only thing that says which kind of report an
-- amendment restates, because the Clerk index links an amendment to nothing (#463).
with covered as (
    select
        doc_id,
        {{ mogov.regex_extract(
            'lower(line_text)',
            'period covered: *([0-9]{1,2}/[0-9]{1,2}/[0-9]{4}) *[^0-9]+ *[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}',
        ) }} as period_start_text,
        {{ mogov.regex_extract(
            'lower(line_text)',
            'period covered: *[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} *[^0-9]+ *([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})',
        ) }} as period_end_text
    from {{ ref('stg_house_fd__pdf_lines') }}
    where has_text and lower(line_text) like 'period covered:%'
)

select
    doc_id,
    min({{ mogov.parse_date('period_start_text', '%m/%d/%Y') }}) as period_start,
    min({{ mogov.parse_date('period_end_text', '%m/%d/%Y') }}) as period_end
from covered
group by doc_id
