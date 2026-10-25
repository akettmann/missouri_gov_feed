-- One row per RSMo section version listed in force on the Revisor's chapter pages. A section can have several
-- versions at once (bid = the Revisor's version id): a later version not yet effective, or conflicting
-- enactments of one section in the same year. section_id is the section number as the Revisor prints it
-- ("1.010", "1.1001", "67.1360"). effective_date is the version's effective date; history_note the session-law
-- history footnote ("(RSMo 1939 § 645, A.L. 1957 p. 587, A.L. 2015 S.B. 239)"), when the first footnote is one.
with src as (
    select
        {{ mogov.json_str('payload', '$.section') }} as section_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.bid'), dbt.type_int()) }} as bid,
        {{ mogov.json_str('payload', '$.chapter') }} as chapter,
        {{ mogov.json_str('payload', '$.title_line') }} as title_line,
        {{ mogov.json_str('payload', '$.effective') }} as effective_line,
        {{ mogov.json_str('payload', '$.historical') }} as historical,
        {{ mogov.json_str('payload', '$.heading') }} as heading_line,
        {{ mogov.json_str('payload', '$.text') }} as section_text,
        {{ mogov.json_str('payload', '$.footnotes[0]') }} as first_footnote,
        {{ mogov.json_fragment('payload', '$.footnotes') }} as footnotes,
        source_url
    from {{ source('mo_revisor', 'sections') }}
)

select
    section_id,
    bid,
    section_id || '/' || {{ dbt.safe_cast('bid', dbt.type_string()) }} as section_version_id,
    chapter,
    {{ dbt.split_part('title_line', "' '", 2) }} as title_numeral,
    -- "1.010. Common law in force — effect on statutes. —" -> "Common law in force — effect on statutes."
    {{ mogov.regex_replace_all(
        mogov.regex_replace_all('heading_line', '^[0-9A-Za-z]+\\.[0-9A-Za-z-]+\\. *', ''), ' *—$', ''
    ) }} as heading,
    {{ mogov.parse_date(mogov.regex_extract('effective_line', '([0-9]{1,2} [A-Z][a-z]{2} [0-9]{4})'), '%d %b %Y') }}
        as effective_date,
    {{ dbt.safe_cast(mogov.regex_extract('effective_line', '([0-9]+) histor'), dbt.type_int()) }} as history_count,
    coalesce(historical = 'true', false) as is_historical,
    effective_line,
    section_text,
    case when first_footnote like '(%' then first_footnote end as history_note,
    footnotes,
    source_url
from src
