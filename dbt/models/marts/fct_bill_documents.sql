-- Links to the PDFs for each bill, one row per document (the PDFs themselves are not fetched): the House's summaries,
-- fiscal notes, witness forms, bill text versions, amendments and the change maps of text versions and amendments,
-- and the Senate's bill text, fiscal note and amendment links.
-- source_site says whose link it is: 'house' (documents.house.mo.gov; House bills and the Senate bills the House
-- acted on, 2024 sessions on) or 'senate' (senate.mo.gov, from the Senate's own bill pages once the mo_senate_bills
-- loader has landed a session; every Senate bill of that session). A Senate bill both sites list has links from both:
-- different URLs, so both rows are kept. The Senate's summaries are text on the page with no link, so they are not
-- rows here (stg_mo_senate__bill_summaries). Witness forms name citizens, so only the link is kept. The XML sometimes
-- lists one link twice (a summary shared by two versions): a link is
-- one row, with its lowest index and the label at that index.
-- The fetched PDFs' size and extraction result are joined by URL (page_count, text_length, has_text, fetch_error;
-- null when the mo_house_pdf loader has not fetched the link, which it never does for witness forms and change maps).
-- The text itself is in fct_bill_document_texts.
-- document_kind: summary, fiscal_note, witness_form, bill_text, text_map, amendment, amendment_map
with documents as (
    select
        session_code,
        bill,
        'summary' as document_kind,
        summary_url as document_url,
        document_name as label,
        summary_index as document_index,
        'house' as source_site
    from {{ ref('stg_mo_house__bill_summaries') }}

    union all

    select
        session_code,
        bill,
        'fiscal_note' as document_kind,
        fiscal_note_url as document_url,
        cast(null as {{ dbt.type_string() }}) as label,
        fiscal_note_index as document_index,
        'house' as source_site
    from {{ ref('stg_mo_house__bill_fiscal_notes') }}

    union all

    select
        session_code,
        bill,
        'witness_form' as document_kind,
        witness_forms_url as document_url,
        description as label,
        witness_index as document_index,
        'house' as source_site
    from {{ ref('stg_mo_house__bill_witness_forms') }}

    union all

    select
        session_code,
        bill,
        'bill_text' as document_kind,
        text_url as document_url,
        coalesce(web_name, document_name) as label,
        text_index as document_index,
        'house' as source_site
    from {{ ref('stg_mo_house__bill_texts') }}
    where text_url is not null

    union all

    select
        session_code,
        bill,
        'text_map' as document_kind,
        map_url as document_url,
        coalesce(web_name, document_name) as label,
        text_index as document_index,
        'house' as source_site
    from {{ ref('stg_mo_house__bill_texts') }}
    where map_url is not null

    union all

    select
        session_code,
        bill,
        'amendment_map' as document_kind,
        map_url as document_url,
        description as label,
        amendment_index as document_index,
        'house' as source_site
    from {{ ref('stg_mo_house__bill_amendments') }}
    where map_url is not null

    union all

    select
        session_code,
        bill,
        'amendment' as document_kind,
        amendment_url as document_url,
        description as label,
        amendment_index as document_index,
        'house' as source_site
    from {{ ref('stg_mo_house__bill_amendments') }}
    where amendment_url is not null

    union all

    select
        session_code,
        bill,
        'bill_text' as document_kind,
        document_url,
        label,
        doc_index + 1 as document_index,
        'senate' as source_site
    from {{ ref('stg_mo_senate__bill_texts') }}
    where document_url is not null and session_code is not null

    union all

    select
        session_code,
        bill,
        'fiscal_note' as document_kind,
        document_url,
        label,
        doc_index + 1 as document_index,
        'senate' as source_site
    from {{ ref('stg_mo_senate__bill_fiscal_notes') }}
    where document_url is not null and session_code is not null

    union all

    select
        session_code,
        bill,
        'amendment' as document_kind,
        document_url,
        label,
        doc_index + 1 as document_index,
        'senate' as source_site
    from {{ ref('stg_mo_senate__bill_amendments') }}
    where document_url is not null and session_code is not null
),

ranked as (
    select
        *,
        row_number() over (
            partition by session_code, bill, document_kind, document_url
            order by document_index, source_site, label
        ) as link_rank
    from documents
)

select
    r.session_code,
    r.bill,
    r.document_kind,
    r.document_url,
    r.document_index,
    r.label,
    r.source_site,
    t.page_count,
    t.text_length,
    t.has_text,
    t.fetch_error
from ranked as r
left join {{ ref('stg_mo_house__document_texts') }} as t
    on trim(r.document_url) = t.document_url and r.document_kind = t.document_kind
where r.link_rank = 1
