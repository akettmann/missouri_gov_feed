-- Missouri judicial circuit of every county, from the Official Manual's "Circuit courts by county" table
-- ("Adair......... Circuit No. 2"; St. Louis appears as "St. Louis Co." and "St. Louis City"). Lines can
-- carry a stray character from the neighbouring column, so the name is taken from its first capital
-- letter. county_key matches stg_census_tiger__features names through name_key(), minus "county"/"co".
with rows as (
    select
        edition,
        trim({{ mogov.regex_extract('line_text', "([A-Z][A-Za-z.' ]*?) *[.]{3,} *Circuit No[.] *[0-9]+", 1) }})
            as county_name,
        {{ dbt.safe_cast(mogov.regex_extract('line_text', 'Circuit No[.] *([0-9]+)', 1), dbt.type_int()) }}
            as circuit_number,
        source_url
    from {{ ref('stg_bluebook__lines') }}
    where
        chapter = 'judicial'
        and {{ mogov.regex_matches('line_text', '[.]{3,} *Circuit No[.] *[0-9]+') }}
),

latest as (
    select max(edition) as edition from rows
)

select distinct
    r.county_name,
    {{ mogov.regex_replace_all(mogov.name_key('r.county_name'), ' (county|co)$', '') }} as county_key,
    r.circuit_number,
    r.edition,
    r.source_url
from rows as r
inner join latest as l on r.edition = l.edition
