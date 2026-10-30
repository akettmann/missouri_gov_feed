-- A committee is not its own donor (#833): no received row may link its counterparty to the committee that
-- received the gift. source_url carries the receiving committee's MECID, so this covers both the TAP and the
-- MEC direct paths on real data (the direct path is gated by the mec_direct var).
select
    official_id,
    source_record_id,
    counterparty_mec_committee_id
from {{ ref('fct_campaign_finance') }}
where
    direction = 'received'
    and counterparty_mec_committee_id is not null
    and source_url like '%MECID=' || counterparty_mec_committee_id
