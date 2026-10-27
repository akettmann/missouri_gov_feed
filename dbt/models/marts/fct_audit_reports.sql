-- One row per State Auditor report with its performance rating, for the report's audited entity. The officeholders an
-- audit of a statewide office is credited to are in fct_audit_report_officeholders (everyone in office during the
-- audit period, or in the window before release where the title names no period): there can be several, so
-- they are rows there, and this table carries only how many and on what basis. County audits are never linked to
-- officials: the Auditor's own summary says a county rating "does not indicate the performance of any one elected
-- official or county office".
with holders as (
    select
        report_number,
        max(link_basis) as officeholder_link_basis,
        {{ dbt.safe_cast('count(*)', dbt.type_int()) }} as officeholder_count
    from {{ ref('fct_audit_report_officeholders') }}
    group by report_number
)

select
    r.report_number,
    r.report_number_display,
    r.report_year,
    r.release_date,
    r.title,
    r.entity_type,
    r.office,
    r.audit_period_start,
    r.audit_period_end,
    r.rating,
    r.rating_level,
    r.rating_status,
    r.rating_sentence,
    r.rating_page,
    r.rating_pdf_url,
    r.full_report_url,
    r.citizens_summary_url,
    h.officeholder_link_basis,
    coalesce(h.officeholder_count, 0) as officeholder_count
from {{ ref('int_mo_auditor__reports') }} as r
left join holders as h on r.report_number = h.report_number
