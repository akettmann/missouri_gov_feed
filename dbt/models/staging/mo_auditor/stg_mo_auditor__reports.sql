-- State Auditor reports from the SearchAudits list, one row per report. report_number is the compact number
-- (2018063); report_number_display the printed one (2018-063). The release timestamp is the Auditor's local
-- clock with no zone, so only its date is kept. A report with a summary PDF links it; the full report url is
-- resolved from the list's relative "~/Repository/Press/..." path (a few reports link off-site).
with src as (
    select
        trim({{ mogov.json_str('payload', '$.rpt_number') }}) as report_number,
        trim({{ mogov.json_str('payload', '$.ReportNumberDisplay') }}) as report_number_display,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.search_year'), dbt.type_int()) }} as search_year,
        {{ mogov.json_str('payload', '$.release_datetime') }} as release_datetime_text,
        trim({{ mogov.json_str('payload', '$.title') }}) as title,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.citz_sum_fk'), dbt.type_int()) }} as citizens_summary_id,
        {{ mogov.json_str('payload', '$.full_rpt_link') }} as full_report_link,
        {{ mogov.json_str('payload', '$.FullReportLinkExternal') }} as report_viewer_url,
        source_url
    from {{ source('mo_auditor', 'reports') }}
)

select
    report_number,
    report_number_display,
    {{ dbt.safe_cast('substring(report_number, 1, 4)', dbt.type_int()) }} as report_year,
    search_year,
    {{ dbt.safe_cast('substring(release_datetime_text, 1, 10)', 'date') }} as release_date,
    title,
    citizens_summary_id,
    case
        when citizens_summary_id is not null
            then
                'https://auditor.mo.gov/AuditReport/CitzSummaryDirect?id='
                || {{ dbt.safe_cast('citizens_summary_id', dbt.type_string()) }}
    end as citizens_summary_url,
    case
        when full_report_link like '~/%' then 'https://auditor.mo.gov' || substring(full_report_link, 2)
        else full_report_link
    end as full_report_url,
    report_viewer_url,
    source_url
from src
