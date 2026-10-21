-- Ties built from AO-10 disclosures must be readable: unreadable OCR text (mogov.is_garbled_text) is filtered
-- out via fct_disclosures.is_garbled. Any row returned is garbage that reached a ties fact.
select
    'fct_commercial_ties' as model,
    official_id,
    detail as txt
from {{ ref('fct_commercial_ties') }}
where source = 'Federal judicial financial disclosure (AO-10)' and {{ mogov.is_garbled_text('detail') }}

union all

select
    'fct_family_ties' as model,
    official_id,
    organization as txt
from {{ ref('fct_family_ties') }}
where source = 'Federal judicial financial disclosure (AO-10)' and {{ mogov.is_garbled_text('organization') }}
