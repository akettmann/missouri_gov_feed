-- Sanity check: witness forms only from the 2021 sessions on (session code 211 up). The House's XML has none for the
-- 2017-2020 sessions (171 to 204); a witness form there means a session's links were mislabeled or the House began
-- publishing back-dated forms (then move the bound, after looking).
select
    session_code,
    bill,
    document_url
from {{ ref('fct_bill_documents') }}
where document_kind = 'witness_form' and session_code < '211'
