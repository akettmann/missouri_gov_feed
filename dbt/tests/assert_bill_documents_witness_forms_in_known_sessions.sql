-- Sanity check: witness forms only from the 2021 sessions on (session code 211 up). The XML has no Witness elements
-- before session 211 (sessions 171 to 204); it is not confirmed that the House only began publishing witness forms in
-- 2021. A witness form there means a session's links were mislabeled or the House began publishing back-dated forms
-- (then move the bound, after looking). Session codes compare as strings, fine while codes stay three digits.
select
    session_code,
    bill,
    document_url
from {{ ref('fct_bill_documents') }}
where document_kind = 'witness_form' and session_code < '211'
