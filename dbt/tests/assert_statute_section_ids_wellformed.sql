-- Sanity check: RSMo section numbers are chapter.section ("1.010", "1.1001", "30A.010"; the uniform codes number
-- sections article-section: "400.3-505", "456.4A-411", "456.4-411A"), and the bills the Revisor's history notes name
-- are HB/SB/HJR/SJR/HCR/SCR + a number. Anything else means the chapter pages or the citation parser picked up the
-- wrong text.
select
    'section' as kind,
    section_id as value
from {{ ref('fct_statute_sections') }}
where not {{ mogov.regex_matches('section_id', '^[0-9]+[A-Z]?\\.[0-9]+[A-Z]?(-[0-9]+[A-Z]?)?$') }}

union all

select
    'bill' as kind,
    bill as value
from {{ ref('fct_bill_statute_links') }}
where not {{ mogov.regex_matches('bill', '^(HB|SB|HJR|SJR|HCR|SCR)[0-9]+$') }}
