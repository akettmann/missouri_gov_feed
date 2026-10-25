-- Share of current officials with an attributed MEC committee (int_mec__official_committees), by office
-- group. Floors are shares of the group, not head counts, so roster churn (elections, appointees,
-- resignations) moves numerator and denominator together instead of eroding fixed counts.
-- Issue #96: a build without the MEC crosswalk (var mec_direct off) showed 295 -> 243 attributed officials.
-- (Root cause: dbt was run without mogov's vars; no code regression.)
--
-- Measured October 2026 (595 current officials). attributed = any committee; exact = linked through MEC's
-- candidate<->committee crosswalk (confidence 'exact (MEC crosswalk)'); name-only = the same data built
-- with mec_direct off, where nothing can be exact:
--                         officials  attributed  exact      name-only attributed
--   state_house               155    144 (93%)   127 (82%)  107 (69%)
--   state_senate               33     33 (100%)   30 (91%)   29 (88%)
--   statewide (6 offices)       6      6 (100%)    6 (100%)   3 (50%)
--
-- Floors (share of officials in the group), and the margin under the measurement:
--                         mec_direct on                           mec_direct off
--                         attributed       exact                  attributed       exact
--   state_house           0.80 (-12.9)     0.65 (-16.9)           0.35 (-34.0)     none
--   state_senate          0.85 (-15.0)     0.70 (-20.9)           0.65 (-22.9)     none
--   statewide             0.65 (-35.0)     0.65 (-35.0)           0.30 (-20.0)     none
-- Rationale:
--   * The exact floor is what detects a lost or broken crosswalk while mec_direct is true: without the
--     crosswalk nothing is exact (0%), whereas the attributed share alone barely moves in the senate
--     (100% -> 88%) and can't tell the modes apart there. Exact floors sit 17-35 points under measured
--     and attributed floors 13-35 points under, enough for turnover of a few seats.
--   * Statewide is six seats, so a share is coarse: 0.65 needs 4 of 6, tolerating two without a match (a
--     new appointee, or an officeholder with no committee yet) but not a missing crosswalk (exact 0 of 6).
--   * mec_direct off has no exact floor, and its shares DECAY as TAP ages: the name match reads TAP
--     contributions, which stop at 2022, so members first seated after that match far less often (house
--     members first seated in 2025 name-match 18/54 = 33%, the 2023 cohort 33/40, pre-2023 about 93%).
--     Projected house name-only share is about 0.51-0.55 in Jan 2027 and about 0.40 in Jan 2029, so the
--     off-mode house floor is 0.35, not tighter. Revisit these off-mode floors every election cycle
--     (senate 0.65 and statewide 0.30 are less exposed but not immune).
--   * The 'other' group (judges, mayors) has no floor: retention judges rarely run committees (about a
--     third of circuit judges are attributed, mostly by name match), so the share is noisy and says little
--     about the pipeline. The legislature and statewide offices are the canaries.
-- The floors follow the mec_direct var, so a run with mec_direct off (only possible when raw MEC data is
-- absent or the on-run-start guard is skipped with skip_optional_raw_check) uses the low name-match floors.
-- Running dbt without mogov's vars (the #96 trigger) is caught by that guard (issue #105, PR #115:
-- check_optional_inputs), not by this test, which only guards the crosswalk while mec_direct is true.
-- Fails when an office group has no officials, or a share is below its floor.
with floors as (
    select
        'state_house' as office_group,
        {{ 0.80 if var('mec_direct', false) else 0.35 }} as min_attributed_share,
        {{ 0.65 if var('mec_direct', false) else 0.0 }} as min_exact_share
    union all
    select
        'state_senate' as office_group,
        {{ 0.85 if var('mec_direct', false) else 0.65 }} as min_attributed_share,
        {{ 0.70 if var('mec_direct', false) else 0.0 }} as min_exact_share
    union all
    select
        'statewide' as office_group,
        {{ 0.65 if var('mec_direct', false) else 0.30 }} as min_attributed_share,
        {{ 0.65 if var('mec_direct', false) else 0.0 }} as min_exact_share
),

committee_links as (
    select
        official_id,
        max(case when confidence like 'exact%' then 1 else 0 end) as is_exact
    from {{ ref('int_mec__official_committees') }}
    group by 1
),

officials as (
    select
        case
            when c.office in ('state_house', 'state_senate') then c.office
            else 'statewide'
        end as office_group,
        count(distinct c.official_id) as n_officials,
        count(distinct l.official_id) as n_attributed,
        count(distinct case when l.is_exact = 1 then l.official_id end) as n_exact
    from {{ ref('int_officials__current') }} as c
    left join committee_links as l on c.official_id = l.official_id
    where
        c.office in (
            'state_house', 'state_senate', 'governor', 'lt_governor', 'secretary_of_state', 'state_auditor',
            'state_treasurer', 'attorney_general'
        )
    group by 1
)

select
    f.office_group,
    f.min_attributed_share,
    f.min_exact_share,
    coalesce(o.n_officials, 0) as n_officials,
    coalesce(o.n_attributed, 0) as n_attributed,
    coalesce(o.n_exact, 0) as n_exact
from floors as f
left join officials as o on f.office_group = o.office_group
where
    coalesce(o.n_officials, 0) = 0
    or 1.0 * o.n_attributed / o.n_officials < f.min_attributed_share
    or 1.0 * o.n_exact / o.n_officials < f.min_exact_share
