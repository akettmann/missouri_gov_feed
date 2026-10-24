-- Officials with at least one attributed MEC committee (int_mec__official_committees), by office group.
-- Issue #96: a build without the MEC crosswalk (var mec_direct off) showed 295 -> 243 attributed officials.
-- (Root cause: dbt was run without mogov's vars; no code regression.)
-- Measured October 2026 (595 current officials), attributed:
--                         mec_direct on     mec_direct off (name match only)
--   state_house (155)     144               107
--   state_senate (33)     33                29
--   statewide (6 offices) 6                 3
-- Floors sit about 15-20% below the measured counts so roster churn and a refresh don't trip them, while
-- losing the crosswalk (or breaking name matching) does. The mec_direct floors catch the crosswalk being
-- lost or broken while mec_direct is true. They do NOT catch dbt being run without mogov's vars (the #96
-- trigger): the floors follow the same var, so a bare build uses the low name-match floors and passes.
-- mogov's cli.py sets the vars from raw_exists('mec_cd1_a'); that gap is tracked in issue #105, and
-- threshold brittleness in #106.
-- Fails when an office group has fewer attributed officials than its floor.
with floors as (
    select
        'state_house' as office_group,
        {{ 120 if var('mec_direct', false) else 85 }} as min_attributed
    union all
    select
        'state_senate' as office_group,
        {{ 25 if var('mec_direct', false) else 20 }} as min_attributed
    union all
    select
        'statewide' as office_group,
        {{ 5 if var('mec_direct', false) else 2 }} as min_attributed
),

attributed as (
    select
        case
            when c.office in ('state_house', 'state_senate') then c.office
            else 'statewide'
        end as office_group,
        count(distinct c.official_id) as n_attributed
    from {{ ref('int_officials__current') }} as c
    inner join {{ ref('int_mec__official_committees') }} as a on c.official_id = a.official_id
    where
        c.office in (
            'state_house', 'state_senate', 'governor', 'lt_governor', 'secretary_of_state', 'state_auditor',
            'state_treasurer', 'attorney_general'
        )
    group by 1
)

select
    f.office_group,
    f.min_attributed,
    coalesce(a.n_attributed, 0) as n_attributed
from floors as f
left join attributed as a on f.office_group = a.office_group
where coalesce(a.n_attributed, 0) < f.min_attributed
