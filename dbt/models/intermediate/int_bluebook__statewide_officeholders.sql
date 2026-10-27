-- Every holder of each statewide elected office since 1820, from the Official Manual's "Historical Listing" tables
-- in the executive chapter (Governors, Lieutenant Governors, Secretaries of State, State Auditors, State Treasurers,
-- Attorneys General). A row looks like "57. Michael L. Parson (R)12 2018–25 Polk 09/17/1955"; the digits after the
-- party are footnote marks. The Manual gives years only, so a term is (start year, end year); end year is null while
-- the person still holds the office. A person who held an office more than once is listed once (the Manual says so),
-- with the whole span. Appointed successors (Wilson 2000, Parson 2018) are rows like any other; the Manual does not
-- date mid-year hand-overs here. Only the latest edition loaded is used.
-- office keys match the statewide_officials seed.
{# a listing row: "57. Michael L. Parson (R)12 2018–25 Polk ..." (footnote marks follow the party, any non-letters) #}
{% set row_start = '^[0-9]{1,2}[.] *' %}
{% set after_party = '[)][^A-Za-z]*?' %}
{% set year = '(?:18|19|20)[0-9]{2}' %}
with lines as (
    select
        edition,
        page,
        page_column,
        line_no,
        line_text,
        source_url,
        case
            when line_text like 'Historical Listing, Governors%' then 'governor'
            when line_text like 'Historical Listing, Lieutenant Governors%' then 'lt_governor'
            when line_text like 'Historical Listing, Secretaries of State%' then 'secretary_of_state'
            when line_text like 'Historical Listing, State Auditors%' then 'state_auditor'
            when line_text like 'Historical Listing, State Treasurers%' then 'state_treasurer'
            when line_text like 'Historical Listing, Attorneys General%' then 'attorney_general'
        end as heading_office
    from {{ ref('stg_bluebook__lines') }}
    where chapter = 'executive'
),

-- a heading opens a section; every later line up to the next heading belongs to its office
numbered as (
    select
        *,
        sum(case when line_text like 'Historical Listing,%' then 1 else 0 end)
            over (partition by edition order by page, page_column, line_no) as section_no
    from lines
),

sectioned as (
    select
        *,
        max(heading_office) over (partition by edition, section_no) as office
    from numbered
),

listed as (
    select
        edition,
        page,
        source_url,
        office,
        line_text,
        {{ mogov.regex_extract('line_text', row_start ~ '(.*?) *[(][A-Za-z]{1,5}' ~ after_party ~ year) }}
            as full_name,
        {{ mogov.regex_extract('line_text', row_start ~ '.*? *[(]([A-Za-z]{1,5})' ~ after_party ~ year) }}
            as party,
        {{ mogov.regex_extract('line_text', after_party ~ '(' ~ year ~ ')') }} as start_year_text,
        {{ mogov.regex_matches('line_text', after_party ~ year ~ '[^0-9 ,]') }} as has_dash,
        {{ mogov.regex_extract('line_text', after_party ~ year ~ '[^0-9 ,]([0-9]{2,4})') }} as end_digits
    from sectioned
    where
        {{ mogov.regex_matches('line_text', row_start ~ '.*? *[(][A-Za-z]{1,5}' ~ after_party ~ year) }}
),

latest as (
    select max(edition) as edition from listed
)

select
    l.edition,
    l.office,
    -- "Denny Hoskins, CPA" -> "Denny Hoskins"
    {{ mogov.regex_replace_all('l.full_name', ', *(CPA|Esq[.]?|M[.]?D[.]?)$', '') }} as full_name,
    l.party,
    {{ dbt.safe_cast('l.start_year_text', dbt.type_int()) }} as term_start_year,
    case
        -- "2025–": still in office
        when l.has_dash and l.end_digits is null then cast(null as {{ dbt.type_int() }})
        -- "1897–1901"
        when {{ dbt.length('l.end_digits') }} = 4 then {{ dbt.safe_cast('l.end_digits', dbt.type_int()) }}
        -- "2018–25": the two-digit year takes the start year's century (and the next one when it would end first)
        when {{ dbt.length('l.end_digits') }} = 2
            then
                {{ dbt.safe_cast('l.start_year_text', dbt.type_int()) }}
                - {{ dbt.safe_cast(dbt.right('l.start_year_text', 2), dbt.type_int()) }}
                + {{ dbt.safe_cast('l.end_digits', dbt.type_int()) }}
                + case
                    when
                        {{ dbt.safe_cast('l.end_digits', dbt.type_int()) }}
                        < {{ dbt.safe_cast(dbt.right('l.start_year_text', 2), dbt.type_int()) }} then 100
                    else 0
                end
        -- "2017": a single year
        else {{ dbt.safe_cast('l.start_year_text', dbt.type_int()) }}
    end as term_end_year,
    l.page,
    l.source_url
from listed as l
inner join latest as t on l.edition = t.edition
where l.office is not null
