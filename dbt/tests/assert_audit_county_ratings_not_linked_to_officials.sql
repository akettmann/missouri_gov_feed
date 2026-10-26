-- The Auditor's county summaries say the rating "does not indicate the performance of any one elected official".
-- Only audits of a statewide office may carry an officeholder; any other audit with one is a modelling error.
select
    report_number,
    entity_type,
    officeholder_at_release_id
from {{ ref('fct_audit_reports') }}
where officeholder_at_release_id is not null and entity_type <> 'statewide_office'
