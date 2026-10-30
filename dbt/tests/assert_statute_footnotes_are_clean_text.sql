-- RSMo footnotes (fct_statute_section_footnotes.footnote_text) are the Revisor's own words and are shown verbatim.
-- None may hold an HTML entity, the U+FFFD replacement character, a control character, a filler value ('~',
-- 'NONE', a one-character note), leading or trailing whitespace or doubled commas and semicolons (",,", ";;"):
-- each means the loader or the staging read the page wrong. Doubled periods are not flagged: the Revisor prints
-- ellipses ("*...*Words ... appear here in original rolls", "..... before turning ....."), quoted case text with
-- elided names ("G....v.Souder") and now and then a typo ("paraphernalia.. State"), all verbatim.
-- A row here: check the page; if the Revisor really prints it, narrow the pattern with a comment saying why.
{% set entity = '&(#[0-9]{1,5}|[A-Za-z]{2,6});' %}

select
    section_version_id,
    footnote_number,
    footnote_text
from {{ ref('fct_statute_section_footnotes') }}
where
    {{ mogov.regex_matches('footnote_text', entity) }}
    or footnote_text like '%�%'
    or {{ mogov.regex_matches('footnote_text', '[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]') }}
    or {{ mogov.regex_matches('footnote_text', ',\\s*,|;\\s*;') }}
    or footnote_text != trim(footnote_text)
    or length(footnote_text) < 2
    or upper(footnote_text) in ('~', 'NONE', 'N/A', 'NULL')
