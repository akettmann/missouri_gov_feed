-- Who held the audited office at the time an audit covers: one row per (State Auditor report of a statewide office,
-- person who held that office). Only audits of a statewide office have rows; a county audit never does (the Auditor's
-- own summary says a county rating "does not indicate the performance of any one elected official").
-- A person is linked when their term overlaps the audit's window. The Official Manual gives terms in whole years,
-- so a term runs from January 15 of its first year (the handover convention of int_officeholders__years: a hand-over
-- in the first days of January does not credit the successor with the predecessor's last audit period) to December 31
-- of its last year, except that a term ending in an inauguration year (2017, 2021, 2025; the auditor's 2019, 2023)
-- ends on January 15, the regular January hand-over. A mid-term change (Parson, June 2018) has no date in the Manual,
-- so the statewide_office_handovers seed gives the exact dates (Hawley's term ended 2019-01-03, not December 31);
-- a change not in the seed credits both people for that whole year. link_basis says where the window comes from:
--   audit_period     the period named in the report title ("Period July 1, 2022 through January 9, 2023", "Year
--                    Ended June 30, 2015"): every officeholder in office at any time in it
--   release_window   the title names no period (most reports): every officeholder in office from January 1 of the
--                    year before the release through the release date. An audit covers earlier time than its
--                    release, so this is deliberately wider than "in office at release", but it is a guess
--                    at the period, not the period.
-- official_id is the person's dim_official id when they also hold a tracked office today (matched on first and last
-- name, or on a known variant such as "Josh Hawley" for Open States' "Joshua"; null for people who left public
-- life), so a former officeholder who is now a senator links to a profile.
{% set start_year_text = dbt.safe_cast('b.term_start_year', dbt.type_string()) %}
{% set end_year_text = dbt.safe_cast('b.term_end_year', dbt.type_string()) %}
{% set family_of_holder = mogov.name_key(mogov.regex_extract('b.full_name', '([^ ]+)$')) %}
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
),

holders as (
    select
        b.office,
        b.full_name,
        b.party,
        b.term_start_year,
        b.term_end_year,
        coalesce(
            o.term_start,
            {{ dbt.safe_cast(dbt.concat([start_year_text, "'-01-15'"]), 'date') }}
        ) as term_start,
        coalesce(
            o.term_end,
            case
                when b.term_end_year is null then {{ dbt.safe_cast("'9999-12-31'", 'date') }}
                -- a term that ends in an inauguration year ends at the January hand-over (the auditor's inaugurations
                -- are in years 3 mod 4, the others' 1 mod 4); any other end year is a mid-term change not in the seed
                when mod(b.term_end_year, 4) = case b.office when 'state_auditor' then 3 else 1 end
                    then
                        {{ dbt.safe_cast(dbt.concat([end_year_text, "'-01-15'"]), 'date') }}
                else
                    {{ dbt.safe_cast(dbt.concat([end_year_text, "'-12-31'"]), 'date') }}
            end
        ) as term_end,
        {{ mogov.name_key(dbt.split_part('b.full_name', "' '", 1)) }} as given_key,
        {{ family_of_holder }} as family_key
    from {{ ref('int_bluebook__statewide_officeholders') }} as b
    left join {{ ref('statewide_office_handovers') }} as o
        on
            b.office = o.office
            and b.term_start_year = o.term_start_year
            and {{ mogov.name_key(mogov.regex_extract('b.full_name', '([^ ]+)$')) }}
            = {{ mogov.name_key('o.family_name') }}
),

-- current officials by name; a key that fits two officials is dropped rather than guessed. Both "first last" as the
-- Manual prints it ("Josh Hawley", whom Open States calls Joshua) and the official's other known variants match.
name_matches as (
    select
        variant_key as match_key,
        official_id
    from {{ ref('int_officials__name_keys') }}
    union
    select
        given_key || ' ' || family_key as match_key,
        official_id
    from {{ ref('int_officials__name_keys') }}
),

current_by_name as (
    select
        match_key,
        min(official_id) as official_id
    from name_matches
    group by match_key
    having count(distinct official_id) = 1
)

select
    w.report_number,
    w.office,
    h.full_name,
    h.party,
    c.official_id,
    h.term_start_year,
    h.term_end_year,
    w.link_basis,
    w.window_start,
    w.window_end
from windows as w
inner join holders as h
    on
        w.office = h.office
        and w.window_end >= h.term_start
        and w.window_start <= h.term_end
left join current_by_name as c on h.given_key || ' ' || h.family_key = c.match_key
