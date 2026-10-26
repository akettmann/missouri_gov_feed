-- Sanity bounds from the State Auditor list (about 90-150 reports a year; ratings are one level of four):
--   * no year has more than 400 reports (a lost year filter, so the 1,000-row cap, would show as one huge year);
--   * a report's number begins with the year it was released in, give or take the turn of the year;
--   * a rated report has its sentence and page, and rating_level is null exactly when rating is.
with per_year as (
    select
        cast(report_year as {{ dbt.type_string() }}) as problem_key,
        'more than 400 reports in one year' as problem
    from {{ ref('fct_audit_reports') }}
    group by report_year
    having count(*) > 400
),

per_report as (
    select
        report_number as problem_key,
        case
            when abs(extract(year from release_date) - report_year) > 1 then 'release date far from report year'
            when rating is not null and (rating_sentence is null or rating_page is null) then 'rating, no provenance'
            when (rating is null) <> (rating_level is null) then 'rating and rating_level disagree'
        end as problem
    from {{ ref('fct_audit_reports') }}
)

select
    problem_key,
    problem
from per_year
union all
select
    problem_key,
    problem
from per_report
where problem is not null
