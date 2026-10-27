-- The Auditor's county summaries say the rating "does not indicate the performance of any one elected official".
-- Only audits of a statewide office may carry an officeholder; any other audit with one is a modelling error.
select
    r.report_number,
    r.entity_type,
    r.officeholder_count
from {{ ref('fct_audit_reports') }} as r
where r.officeholder_count > 0 and r.entity_type <> 'statewide_office'
union all
select
    o.report_number,
    r.entity_type,
    1 as officeholder_count
from {{ ref('fct_audit_report_officeholders') }} as o
left join {{ ref('fct_audit_reports') }} as r on o.report_number = r.report_number
where r.entity_type is null or r.entity_type <> 'statewide_office'
