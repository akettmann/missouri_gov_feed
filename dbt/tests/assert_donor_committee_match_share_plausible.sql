-- Share of committee-to-committee dollars whose donor name resolves to one Missouri committee
-- (int_mec__donor_committees). Measured October 2026, both MEC feeds (TAP 2011-2022 + MEC direct 2023-2026,
-- $489M from committees): matched 71.1%, ambiguous 1.4%, not active that year 0.6%, no match 26.9%
-- (mostly federal and out-of-state PACs, which don't file with MEC). TAP alone (mec_direct off, $385M;
-- measured before the alias tier): matched 68.3%, ambiguous 0.8%. Exact names alone matched about 46%
-- (#9).
-- Fails when:
--   matched < 55%   a normalization rule or the filer-name list broke and links were lost
--   matched > 85%   a key collapsed (e.g. to a few common words) and names now match the wrong committee
--   ambiguous > 5%  the tiers stopped telling committees apart (active years not applied?)
with shares as (
    select
        sum(amount) as total_amount,
        sum(case when match_status = 'matched' then amount else 0 end) as matched_amount,
        sum(case when match_status = 'ambiguous' then amount else 0 end) as ambiguous_amount
    from {{ ref('int_mec__donor_committees') }}
)

select
    total_amount,
    matched_amount,
    ambiguous_amount
from shares
where
    total_amount > 0
    and (
        matched_amount < 0.55 * total_amount
        or matched_amount > 0.85 * total_amount
        or ambiguous_amount > 0.05 * total_amount
    )
