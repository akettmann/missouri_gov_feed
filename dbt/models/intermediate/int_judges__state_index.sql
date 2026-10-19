-- Missouri state judges from the Official Manual's alphabetical judge index:
--   "Crane, Sue M. ........ Associate ....... 13th   Harrell, Kevin D. ....... Circuit ....... 16th"
-- Each index line holds up to two entries. Entries whose name wrapped onto two lines are lost
-- (a handful per edition); compare the count against the manual's chapter totals when reviewing.
-- The dot leader sometimes runs straight into the circuit ("Associate ..............35th"), so the space before
-- it is optional; without that, 7 judges in the 2025-2026 edition lost their circuit.
{% set entry = "([A-Z][A-Za-z'.-]+(?: [A-Za-z'.-]+)*, [A-Za-z'. -]+?) [.]{3,} (Associate|Circuit|Supreme Court|Appellate Eastern|Appellate Western|Appellate Southern)(?: [.]{3,} ?([0-9]+)(?:st|nd|rd|th))?" %}  -- noqa: LT05

with index_lines as (
    select
        edition,
        page,
        line_no,
        line_text,
        source_url
    from {{ ref('stg_bluebook__lines') }}
    where chapter = 'judicial' and line_text like '%....%'
),

entries as (
    select
        edition,
        source_url,
        {{ mogov.regex_extract('line_text', '^' ~ entry, 1) }} as index_name,
        {{ mogov.regex_extract('line_text', '^' ~ entry, 2) }} as court_kind,
        {{ mogov.regex_extract('line_text', '^' ~ entry, 3) }} as circuit
    from index_lines
    union all
    select
        edition,
        source_url,
        {{ mogov.regex_extract('line_text', entry ~ ' +' ~ entry ~ '$', 4) }} as index_name,
        {{ mogov.regex_extract('line_text', entry ~ ' +' ~ entry ~ '$', 5) }} as court_kind,
        {{ mogov.regex_extract('line_text', entry ~ ' +' ~ entry ~ '$', 6) }} as circuit
    from index_lines
),

named as (
    select
        edition,
        source_url,
        trim(index_name) as index_name,
        court_kind,
        circuit,
        trim({{ dbt.split_part('index_name', "','", 1) }}) as family_name,
        trim({{ dbt.split_part('index_name', "','", 2) }}) as given_names
    from entries
    where index_name is not null
)

select distinct
    edition,
    source_url,
    index_name,
    family_name,
    given_names,
    trim(given_names || ' ' || family_name) as full_name,
    court_kind,
    circuit,
    case
        when court_kind = 'Supreme Court' then 'mo_supreme_court'
        when court_kind like 'Appellate%' then 'mo_court_of_appeals'
        when court_kind = 'Circuit' then 'mo_circuit_judge'
        else 'mo_associate_circuit_judge'
    end as office,
    case
        when court_kind = 'Supreme Court' then 'Judge, Supreme Court of Missouri'
        when court_kind like 'Appellate%'
            then
                'Judge, Missouri Court of Appeals, ' || replace(court_kind, 'Appellate ', '') || ' District'
        when court_kind = 'Circuit' then 'Circuit Judge, ' || circuit || ' Judicial Circuit'
        else 'Associate Circuit Judge, ' || circuit || ' Judicial Circuit'
    end as office_title
from named
