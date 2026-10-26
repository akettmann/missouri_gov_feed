-- A report PDF that cannot be fetched (extraction_status http_<code>) is a rare dead link on the Auditor's site
-- (2013-009 returned 404 once), not a pattern. More than 10 of them across all reports means the site changed its
-- urls or is blocking us, and the missing ratings would go unnoticed. Warns, so a bad day does not stop the build.
{{ config(severity='warn') }}

select count(*) as fetch_failures
from {{ ref('stg_mo_auditor__ratings') }}
where substr(extraction_status, 1, 5) = 'http_'
having count(*) > 10
