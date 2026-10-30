-- Sanity check: the Senate document labels, titles and statuses (staged with the shared text macros) have no
-- HTML entities, no U+FFFD, no filler value ('~', 'NONE', a one-character label) and no doubled commas or semicolons. A
-- bare '&' is real ("offered & adopted"), so only entity forms count. Returns the offending rows.
with texts as (
    select
        'bill_texts' as model,
        session_code,
        bill,
        doc_index,
        label as txt
    from {{ ref('stg_mo_senate__bill_texts') }}
    union all
    select
        'bill_texts' as model,
        session_code,
        bill,
        doc_index,
        title as txt
    from {{ ref('stg_mo_senate__bill_texts') }}
    union all
    select
        'bill_texts' as model,
        session_code,
        bill,
        doc_index,
        version as txt
    from {{ ref('stg_mo_senate__bill_texts') }}
    union all
    select
        'bill_fiscal_notes' as model,
        session_code,
        bill,
        doc_index,
        label as txt
    from {{ ref('stg_mo_senate__bill_fiscal_notes') }}
    union all
    select
        'bill_fiscal_notes' as model,
        session_code,
        bill,
        doc_index,
        title as txt
    from {{ ref('stg_mo_senate__bill_fiscal_notes') }}
    union all
    select
        'bill_amendments' as model,
        session_code,
        bill,
        doc_index,
        label as txt
    from {{ ref('stg_mo_senate__bill_amendments') }}
    union all
    select
        'bill_amendments' as model,
        session_code,
        bill,
        doc_index,
        title as txt
    from {{ ref('stg_mo_senate__bill_amendments') }}
    union all
    select
        'bill_amendments' as model,
        session_code,
        bill,
        doc_index,
        status as txt
    from {{ ref('stg_mo_senate__bill_amendments') }}
    union all
    select
        'bill_summaries' as model,
        session_code,
        bill,
        doc_index,
        label as txt
    from {{ ref('stg_mo_senate__bill_summaries') }}
)

select
    model,
    session_code,
    bill,
    doc_index,
    txt
from texts
where
    txt is not null
    and (
        {{ mogov.regex_matches('txt', '&(amp|lt|gt|quot|apos|nbsp|#[0-9]+);') }}
        or txt like '%�%'
        or upper(trim(txt)) in ('~', 'NONE', 'N/A', 'NA', '')
        or length(trim(txt)) < 2
        or txt like '%,,%'
        or txt like '%;;%'
    )
