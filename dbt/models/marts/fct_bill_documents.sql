-- Links to the House's PDFs for each bill, one row per document (the PDFs themselves are not fetched):
-- summaries, fiscal notes, witness forms, bill text versions, amendments and the change maps of text versions and
-- amendments.
-- Covers House bills and the Senate bills the House acted on (2024 sessions on). Witness forms name citizens, so
-- only the link is kept. The XML sometimes lists one link twice (a summary shared by two versions): a link is
-- one row, with its lowest index and the label at that index.
-- document_kind: summary, fiscal_note, witness_form, bill_text, text_map, amendment, amendment_map
with documents as (
    select
        session_code,
        bill,
        'summary' as document_kind,
        summary_url as document_url,
        document_name as label,
        summary_index as document_index
    from {{ ref('stg_mo_house__bill_summaries') }}

    union all

    select
        session_code,
        bill,
        'fiscal_note' as document_kind,
        fiscal_note_url as document_url,
        cast(null as {{ dbt.type_string() }}) as label,
        fiscal_note_index as document_index
    from {{ ref('stg_mo_house__bill_fiscal_notes') }}

    union all

    select
        session_code,
        bill,
        'witness_form' as document_kind,
        witness_forms_url as document_url,
        description as label,
        witness_index as document_index
    from {{ ref('stg_mo_house__bill_witness_forms') }}

    union all

    select
        session_code,
        bill,
        'bill_text' as document_kind,
        text_url as document_url,
        coalesce(web_name, document_name) as label,
        text_index as document_index
    from {{ ref('stg_mo_house__bill_texts') }}
    where text_url is not null

    union all

    select
        session_code,
        bill,
        'text_map' as document_kind,
        map_url as document_url,
        coalesce(web_name, document_name) as label,
        text_index as document_index
    from {{ ref('stg_mo_house__bill_texts') }}
    where map_url is not null

    union all

    select
        session_code,
        bill,
        'amendment_map' as document_kind,
        map_url as document_url,
        description as label,
        amendment_index as document_index
    from {{ ref('stg_mo_house__bill_amendments') }}
    where map_url is not null

    union all

    select
        session_code,
        bill,
        'amendment' as document_kind,
        amendment_url as document_url,
        description as label,
        amendment_index as document_index
    from {{ ref('stg_mo_house__bill_amendments') }}
    where amendment_url is not null
),

ranked as (
    select
        *,
        row_number() over (
            partition by session_code, bill, document_kind, document_url
            order by document_index, label
        ) as link_rank
    from documents
)

select
    session_code,
    bill,
    document_kind,
    document_url,
    document_index,
    label
from ranked
where link_rank = 1
