-- Sanity check: share of AO-10 items (investments aside) flagged is_garbled. About 1% are in the 2026-09
-- CourtListener snapshot; more than 5% means the text changed shape (encoding, a new OCR pass) or
-- mogov.is_garbled_text broke, and readable items are being dropped from the ties facts.
select
    count(*) as items,
    sum(case when is_garbled then 1 else 0 end) as garbled
from {{ ref('stg_courtlistener__judge_disclosure_items') }}
where item_kind <> 'investment'
having sum(case when is_garbled then 1 else 0 end) > 0.05 * count(*)
