-- State Auditor reports with their rating and the kind of entity audited. A report has a rating only when its
-- PDF carried the sentence "the overall performance of this entity was ..." (rating_status 'ok'); 'not_read'
-- means the loader never opened a PDF for it (financial statements, monthly filing reports, follow-ups, reports
-- before the 2012 summaries). rating_level orders the Auditor's four levels (Excellent 4 ... Poor 1).
-- entity_type: 'statewide_office' when the title starts with an audited statewide office (seed
-- mo_auditor_statewide_entities), 'county' for a title ending in " County", else 'other' (state agencies, cities,
-- courts, schools, districts, statewide reports). Only a statewide office is ever linked to an officeholder.
-- audit_period_start / audit_period_end: the period the title says the audit covers, when it says one:
--   "Period July 1, 2022 through January 9, 2023"            a final audit of a departing officeholder
--   "Year Ended June 30, 2012", "Three Years Ended June 30, 2003"   whole fiscal years, ending on that date
--   "Period July 1, 2008 to January 12, 2009, and the Two Years Ended June 30, 2008"
--                                       both: the earliest start and the latest end
-- Most titles say nothing ("Office of Governor"); both are then null. A date is "Month d, yyyy"; the month name's
-- first three letters give the month (mogov.month_name_date).
{% set date_re = '[a-z]+ [0-9]{1,2}, ?[0-9]{4}' %}
{% set count_words = 'one|two|three|four|five|six|seven|eight|nine|ten' %}
with reports as (
    select * from {{ ref('stg_mo_auditor__reports') }}
),

-- the date phrases of the title, lower case
title_parts as (
    select
        report_number,
        {{ mogov.regex_extract('lower(title)', 'period (' ~ date_re ~ ') (?:to|through) ' ~ date_re) }}
            as period_from_text,
        {{ mogov.regex_extract('lower(title)', 'period ' ~ date_re ~ ' (?:to|through) (' ~ date_re ~ ')') }}
            as period_to_text,
        {{ mogov.regex_extract('lower(title)', '(?:(' ~ count_words ~ ') )?years? ended ' ~ date_re) }}
            as fy_count_word,
        {{ mogov.regex_extract('lower(title)', 'years? ended (' ~ date_re ~ ')') }} as fy_end_text
    from reports
),

title_dates as (
    select
        report_number,
        {{ mogov.month_name_date('period_from_text') }} as period_from,
        {{ mogov.month_name_date('period_to_text') }} as period_to,
        {{ mogov.month_name_date('fy_end_text') }} as fy_end,
        case coalesce(fy_count_word, 'one')
            when 'one' then 1
            when 'two' then 2
            when 'three' then 3
            when 'four' then 4
            when 'five' then 5
            when 'six' then 6
            when 'seven' then 7
            when 'eight' then 8
            when 'nine' then 9
            when 'ten' then 10
        end as fy_years
    from title_parts
),

audit_periods as (
    select
        report_number,
        -- the day after the same date n years earlier: "Year Ended June 30, 2012" starts July 1, 2011
        case
            when
                fy_end is not null
                then {{ dbt.safe_cast(dbt.dateadd('day', 1, dbt.dateadd('year', '-fy_years', 'fy_end')), 'date') }}
        end as fy_start,
        fy_end,
        period_from,
        period_to
    from title_dates
),

audit_period_bounds as (
    select
        report_number,
        case
            when fy_start is null then period_from
            when period_from is null then fy_start
            when fy_start < period_from then fy_start
            else period_from
        end as audit_period_start,
        case
            when fy_end is null then period_to
            when period_to is null then fy_end
            when fy_end > period_to then fy_end
            else period_to
        end as audit_period_end
    from audit_periods
),

ratings as (
    select * from {{ ref('stg_mo_auditor__ratings') }}
)

select
    r.report_number,
    r.report_number_display,
    r.report_year,
    r.release_date,
    r.title,
    b.audit_period_start,
    b.audit_period_end,
    case
        when e.office is not null then 'statewide_office'
        when lower(r.title) like '% county' then 'county'
        else 'other'
    end as entity_type,
    e.office,
    a.rating,
    case a.rating
        when 'Excellent' then 4
        when 'Good' then 3
        when 'Fair' then 2
        when 'Poor' then 1
    end as rating_level,
    coalesce(a.extraction_status, 'not_read') as rating_status,
    a.rating_sentence,
    a.page as rating_page,
    a.pdf_url as rating_pdf_url,
    r.full_report_url,
    r.citizens_summary_url
from reports as r
left join ratings as a on r.report_number = a.report_number
left join audit_period_bounds as b on r.report_number = b.report_number
left join {{ ref('mo_auditor_statewide_entities') }} as e on lower(r.title) like e.title_prefix || '%'
