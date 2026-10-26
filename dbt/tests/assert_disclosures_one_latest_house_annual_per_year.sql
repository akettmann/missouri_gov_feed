-- Sanity check on is_latest_version: a House filer has at most one latest annual-group report per report year.
-- The model does not expose its report group, so this derives the bound from what it does expose: the latest
-- annual/amended reports in a filer-year are the one annual group plus at most one amendment per candidate report
-- filed that year (an amendment of a candidate report sits in that report's own group). More than that means an
-- amendment failed to supersede the report it amends.
with latest as (
    select
        official_id,
        report_year,
        count(distinct document_url) as latest_reports
    from {{ ref('fct_disclosures') }}
    where
        disclosure_type = 'U.S. House financial disclosure'
        and filing_kind in ('annual report', 'amended report')
        and is_latest_version
        and report_year is not null
    group by official_id, report_year
),

candidates as (
    select
        official_id,
        report_year,
        count(distinct document_url) as candidate_reports
    from {{ ref('fct_disclosures') }}
    where
        disclosure_type = 'U.S. House financial disclosure'
        and filing_kind = 'candidate report'
        and report_year is not null
    group by official_id, report_year
)

select
    l.official_id,
    l.report_year,
    l.latest_reports,
    coalesce(c.candidate_reports, 0) as candidate_reports
from latest as l
left join candidates as c
    on l.official_id = c.official_id and l.report_year = c.report_year
where l.latest_reports > 1 + coalesce(c.candidate_reports, 0)
