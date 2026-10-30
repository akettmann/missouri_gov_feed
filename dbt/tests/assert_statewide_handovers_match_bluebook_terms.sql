-- Every statewide_office_handovers row must match a term in the latest Official Manual edition (office, term start
-- year, family name). fct_audit_report_officeholders joins on those three, so a row for a retitled or renamed Manual
-- entry would be silently ignored and the holder would fall back to the year-based convention.
select
    o.office as problem_key,
    o.family_name,
    o.term_start_year
from {{ ref('statewide_office_handovers') }} as o
left join {{ ref('int_bluebook__statewide_officeholders') }} as b
    on
        o.office = b.office
        and o.term_start_year = b.term_start_year
        and {{ mogov.name_key('o.family_name') }} = {{ mogov.name_key(mogov.regex_extract('b.full_name', '([^ ]+)$')) }}
where b.office is null
