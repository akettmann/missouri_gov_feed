-- Who held the audited office at the time an audit covers: one row per (State Auditor report of a statewide office,
-- person who held that office). Only audits of a statewide office have rows; a county audit never does (the Auditor's
-- own summary says a county rating "does not indicate the performance of any one elected official").
-- A person is linked when their term overlaps the audit's window. The Official Manual gives terms in whole years,
-- so a term runs from the second Monday of January of its first year, the day regular terms begin at noon (RSMo
-- 27.010 sets it for the Attorney General; the other offices follow the same observed swearing-in practice;
-- 2017-01-09, 2021-01-11, 2025-01-13, and 2019-01-14, 2023-01-09 for the auditor), to December 31 of its
-- last year, except that a term ending in an inauguration year (2017, 2021, 2025; the auditor's 2019, 2023) ends on
-- that day. The hand-over day is shared, but an audit window that ends on it belongs to the outgoing holder only
-- (an audit "through January 9, 2017" is the last period of the officeholder leaving that day, not the successor's),
-- so a window must end after a term's first day to count. The dates are worked out in int_statewide__terms.
-- A mid-term change (Parson, June 2018) has no date in the Manual, so the statewide_office_handovers seed gives
-- the exact dates (Hawley's term ended 2019-01-03, not December 31); a change not in the seed credits
-- both people for that whole year. link_basis says where the window comes from:
--   audit_period     the period named in the report title ("Period July 1, 2022 through January 9, 2023", "Year
--                    Ended June 30, 2015"): every officeholder in office at any time in it
--   release_window   the title names no period (most reports): every officeholder in office from January 1 of the
--                    year before the release through the release date. An audit covers earlier time than its
--                    release, so this is deliberately wider than "in office at release", but it is a guess
--                    at the period, not the period.
-- official_id is the person's dim_official id when they also hold a tracked office today (matched on first and last
-- name, or on a known variant such as "Josh Hawley" for Open States' "Joshua"; null for people who left public
-- life), so a former officeholder who is now a senator links to a profile.
{% set prior_year = dbt.safe_cast('extract(year from release_date) - 1', dbt.type_string()) %}
with windows as (
    select
        report_number,
        office,
        release_date,
        case
            when audit_period_end is not null then 'audit_period'
            else 'release_window'
        end as link_basis,
        case
            when audit_period_end is not null then coalesce(audit_period_start, audit_period_end)
            else
                {{ dbt.safe_cast(dbt.concat([prior_year, "'-01-01'"]), 'date') }}
        end as window_start,
        coalesce(audit_period_end, release_date) as window_end
    from {{ ref('int_mo_auditor__reports') }}
    where entity_type = 'statewide_office'
)

select
    w.report_number,
    w.office,
    h.full_name,
    h.party,
    h.official_id,
    h.term_start_year,
    h.term_end_year,
    w.link_basis,
    w.window_start,
    w.window_end
from windows as w
inner join {{ ref('int_statewide__terms') }} as h
    on
        w.office = h.office
        and w.window_end > h.term_start
        and w.window_start <= h.term_end
