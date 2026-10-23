-- Placeholder donor names ('C', '~', '0'; #31) must not reach staging: a one-character name is treated as
-- missing, and so is a name with no letter or number ('~ ~', '- -').
-- A name that starts with a long all-digit token ('79047860 VINCENT'; 6+ digits, so real names like '417 PAC'
-- pass) is a shifted-column row (#60) with a record ID in the first-name column, not a person.
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
    or {{ mogov.regex_matches('contributor_name', '^[0-9]{6,} ') }}
