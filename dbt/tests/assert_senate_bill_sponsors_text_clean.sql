-- Sanity check: Senate sponsor names (staged with the shared name macros) have no HTML entities, no U+FFFD, no filler
-- value ('~', 'NONE', a one-character name), no doubled punctuation and no leftover "(16)"-style district suffix.
-- Returns the offending rows.
select
    session_code,
    bill,
    sponsor_name
from {{ ref('stg_mo_senate__bill_sponsors') }}
where
    {{ mogov.regex_matches('sponsor_name', '&(amp|lt|gt|quot|apos|nbsp|#[0-9]+);') }}
    or sponsor_name like '%�%'
    or upper(trim(sponsor_name)) in ('~', 'NONE', 'N/A', 'NA', '')
    or length(trim(sponsor_name)) < 2
    or sponsor_name like '%,,%'
    or sponsor_name like '%;;%'
    or {{ mogov.regex_matches('sponsor_name', '[(][0-9]+[)]') }}
