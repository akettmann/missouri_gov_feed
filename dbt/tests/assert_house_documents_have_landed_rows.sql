-- Sanity check: once the mo_house_pdf loader has landed any document of a session and kind, it has a row (text, or
-- the error it hit) for every link of that kind in that session, since the loader lists every link and records a
-- failure as a row. A link with no row means the loader skipped it or the document URL changed shape (whitespace,
-- host) between the two. Sessions and kinds the loader has not started are skipped: it runs in pieces and is
-- optional (the 2017-2026 set is about 19 hours of requests). Witness forms and change maps are never fetched. Only the
-- House's links count: the Senate's PDFs are not fetched yet (#590).
with started as (
    select distinct
        session_code,
        document_kind
    from {{ ref('stg_mo_house__document_texts') }}
)

select
    d.session_code,
    d.bill,
    d.document_kind,
    d.document_url
from {{ ref('fct_bill_documents') }} as d
inner join started
    on d.session_code = started.session_code and d.document_kind = started.document_kind
left join {{ ref('stg_mo_house__document_texts') }} as t
    on trim(d.document_url) = t.document_url
where t.document_url is null and d.source_site = 'house'
