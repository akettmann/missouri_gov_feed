-- One row per RSMo section version listed in force on the Revisor's chapter pages. A section can have several
-- versions at once (bid = the Revisor's version id): a later version not yet effective, conflicting enactments
-- of one section in the same year, or an earlier version printed beside one a court held unconstitutional.
-- section_id is the section number as the Revisor prints it ("1.010", "1.1001", "67.1360"). effective_date is the
-- version's effective date; the Revisor dates a version that waits on a contingency 1 Jan 2099, which becomes
-- is_contingent with no date. held_unconstitutional: the effective line says "(all or part is unconstitutional)".
-- history_note is the session-law history footnote ("(RSMo 1939 § 645, A.L. 1957 p. 587, A.L. 2015 S.B. 239)"),
-- when the first footnote is one. footnotes is the page's whole footnote array (stg_mo_revisor__section_footnotes
-- explodes it). fetched_at is when the page was fetched from revisor.mo.gov (the loader records the HTTP cache
-- entry's fetch time, so a page reused from the cache keeps its original time); null on rows loaded before the
-- loader recorded it (#852). loaded_at is when our pipeline last published the raw table, up to 180 days after
-- the fetch.
{{ config(materialized='table') }}
{#- A table, unlike the other staging views: the model parses the payload column of the raw sections table
    (~53 MB of JSON, one document per section version), and fct_statute_sections,
    int_mo_revisor__session_law_bills, stg_mo_revisor__section_footnotes and several tests each re-read it, so as
    a view that parse ran once per consumer (#886). -#}

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
        {{ dbt.safe_cast(mogov.json_str('payload', '$.fetched_at'), 'timestamp with time zone') }} as fetched_at,
        source_url,
        loaded_at
    from {{ source('mo_revisor', 'sections') }}
),

dated as (
    select
        *,
        {{ mogov.parse_date(mogov.regex_extract('effective_line', '([0-9]{1,2} [A-Z][a-z]{2} [0-9]{4})'), '%d %b %Y') }}
            as printed_date
    from src
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
    case when printed_date < cast('2099-01-01' as date) then printed_date end as effective_date,
    coalesce(printed_date >= cast('2099-01-01' as date), false) as is_contingent,
    coalesce(effective_line like '%unconstitutional%', false) as held_unconstitutional,
    {{ dbt.safe_cast(mogov.regex_extract('effective_line', '([0-9]+) histor'), dbt.type_int()) }} as history_count,
    coalesce(historical = 'true', false) as is_historical,
    effective_line,
    section_text,
    case when first_footnote like '(%' then first_footnote end as history_note,
    footnotes,
    source_url,
    fetched_at,
    loaded_at
from dated
