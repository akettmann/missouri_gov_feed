-- Placeholder donor names ('C', '~', '0'; #31) must not reach staging: a one-character name is treated as
-- missing, and so is a name with no letter or number ('~ ~', '- -').
-- Returns offending rows, so the test fails if the cleanup in stg_tap_mec__contributions regresses.
select
    mec_committee_id,
    contributor_name,
    contribution_date,
    amount
from {{ ref('stg_tap_mec__contributions') }}
where
    length(contributor_name) < 2
    or not {{ mogov.regex_matches('contributor_name', '[A-Za-z0-9]') }}
