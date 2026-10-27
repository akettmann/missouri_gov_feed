{{ config(severity='warn') }}

-- A bill whose BILLSTATUS actions say it became law (a 36000/41000 action) but that is not on the laws list. Warns
-- rather than fails: for a just-signed bill in the current Congress GovInfo may add the action before it updates
-- `<laws>`, and the next daily load closes the gap. (The reverse, a law number with no action, happens: 119-hr-766
-- lists 119 S. 766's law, and is not flagged.) Returns a row per bill.
select
    bill_id as problem_key,
    'became law by its actions but not on the laws list' as problem
from {{ ref('int_federal_bills__stage') }}
where became_law_date is not null and not has_law_number
