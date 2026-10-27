-- The enacting-title and Section A clauses the mo_house_pdf loader read (stg_mo_house__statute_refs.clause_text) are
-- statute-reference prose from the House's PDFs. None may hold an HTML entity, the U+FFFD replacement character, a
-- control character, a filler value ('~', 'NONE', a one-character clause) or doubled punctuation (", ,", ",,"):
-- each means the extraction or the parser read the wrong text.
{% set entity = '&(#[0-9]{1,5}|amp|AMP|quot|QUOT|lt|LT|gt|GT|apos|nbsp|NBSP);' %}

select
    document_url,
    ordinal,
    action,
    clause_text
from {{ ref('stg_mo_house__statute_refs') }}
where
    {{ mogov.regex_matches('clause_text', entity) }}
    or clause_text like '%�%'
    or {{ mogov.regex_matches('clause_text', '[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]') }}
    or {{ mogov.regex_matches('clause_text', ',\\s*,|;\\s*;|\\.\\.') }}
    or length(clause_text) < 10
    or upper(clause_text) in ('~', 'NONE', 'N/A', 'NULL')
