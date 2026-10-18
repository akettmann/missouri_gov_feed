-- U.S. Senate eFD report rows (web-filed annual reports and PTRs), one row per table row, with the cells
-- re-keyed by their column header. Paper filings aren't parsed (see stg_senate_efd__filings).
with rows_ as (
    select
        record_key as row_key,
        {{ mogov.json_str('payload', '$.url') }} as document_url,
        {{ mogov.json_str('payload', '$.first_name') }} as first_name,
        {{ mogov.json_str('payload', '$.last_name') }} as last_name,
        {{ mogov.json_str('payload', '$.title') }} as filing_title,
        {{ mogov.parse_date(mogov.json_str('payload', '$.submitted'), '%m/%d/%Y') }} as submitted_date,
        {{ mogov.json_str('payload', '$.section') }} as section,
        payload
    from {{ source('raw', 'senate_efd_rows') }}
),

cells as (
    select
        r.row_key,
        c.idx,
        {{ mogov.json_str('c.value', '$') }} as cell
    from rows_ as r
    cross join lateral {{ mogov.json_elements('r.payload', '$.cells') }} as c
),

headers as (
    select
        r.row_key,
        h.idx,
        {{ mogov.json_str('h.value', '$') }} as header
    from rows_ as r
    cross join lateral {{ mogov.json_elements('r.payload', '$.headers') }} as h
),

keyed as (
    select
        c.row_key,
        lower(h.header) as header,
        c.cell
    from cells as c
    inner join headers as h on c.row_key = h.row_key and c.idx = h.idx
    where coalesce(h.header, '') not in ('', '#') and coalesce(c.cell, '') not in ('', '--')
)

select
    r.row_key,
    r.document_url,
    r.first_name,
    r.last_name,
    r.filing_title,
    r.submitted_date,
    r.section,
    max(case when k.header in ('owner', 'who was paid', 'debtor', 'who received payment?') then k.cell end) as owner,
    max(case when k.header in ('value', 'amount', 'amount paid') then k.cell end) as amount,
    max(case when k.header = 'income' then k.cell end) as income_amount,
    max(case
        when
            k.header in (
                'asset', 'asset name', 'entity', 'who paid', 'creditor', 'source', 'parties involved', 'who paid?'
            )
            then k.cell
    end) as counterparty,
    max(
        case when k.header in ('position held', 'type', 'transaction type', 'asset type', 'income type') then k.cell end
    )
        as item_type,
    max(case when k.header in ('transaction date', 'position dates', 'date', 'incurred') then k.cell end) as item_date,
    {{ dbt.listagg("k.header || ': ' || k.cell", "' | '", "order by k.header") }} as description
from rows_ as r
inner join keyed as k on r.row_key = k.row_key
group by 1, 2, 3, 4, 5, 6, 7
