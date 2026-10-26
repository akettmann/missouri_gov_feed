-- A report title that starts with two seed prefixes (mo_auditor_statewide_entities) would duplicate the report in
-- int_mo_auditor__reports, because the join is on the prefix. Fails with each report that came out more than once.
select
    report_number,
    count(*) as n_rows
from {{ ref('int_mo_auditor__reports') }}
group by report_number
having count(*) > 1
