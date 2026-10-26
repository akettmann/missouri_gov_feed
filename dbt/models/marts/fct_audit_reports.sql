-- One row per State Auditor report with its performance rating, for the report's audited entity. The officeholder is
-- linked only for audits of a statewide office, to whoever held that office on the release date, and only when
-- that person is a current official (fct_office_history holds current officials' careers). The audit may
-- cover the predecessor's term, so the link is "in office when published", not "audited". County audits are
-- never linked to officials: the Auditor's own summary says a county rating "does not indicate the performance
-- of any one elected official or county office".
with holders as (
    select
        r.report_number,
        h.official_id,
        d.full_name,
        row_number() over (partition by r.report_number order by h.start_date desc, h.official_id asc) as rn
    from {{ ref('int_mo_auditor__reports') }} as r
    inner join {{ ref('statewide_officials') }} as s on r.office = s.office
    inner join {{ ref('fct_office_history') }} as h
        on
            lower(h.office_title) in (
                lower(s.office_title),
                'missouri ' || lower(s.office_title),
                lower(s.office_title) || ' of missouri'
            )
            and r.release_date >= h.start_date
            and (h.end_date is null or r.release_date <= h.end_date)
    inner join {{ ref('dim_official') }} as d on h.official_id = d.official_id
    where r.entity_type = 'statewide_office'
)

select
    r.report_number,
    r.report_number_display,
    r.report_year,
    r.release_date,
    r.title,
    r.entity_type,
    r.office,
    r.rating,
    r.rating_level,
    r.rating_status,
    r.rating_sentence,
    r.rating_page,
    r.rating_pdf_url,
    r.full_report_url,
    r.citizens_summary_url,
    h.official_id as officeholder_at_release_id,
    h.full_name as officeholder_at_release_name
from {{ ref('int_mo_auditor__reports') }} as r
left join holders as h on r.report_number = h.report_number and h.rn = 1
