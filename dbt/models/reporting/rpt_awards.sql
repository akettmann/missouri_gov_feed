-- Number-based "awards": the top officials (5 unless the awards_threshold var says otherwise) on one measured
-- number, within one office (House members against House members), per calendar year and over all loaded
-- years, each paired with its opposite. streak_years counts consecutive qualifying yearly periods.
-- Every award ranks a single measured figure; nothing is combined into a score.
--   attendance:        rpt_attendance, present / recorded votes, at least 100 recorded votes in the period, ranked
--                      in the chamber the votes were cast in (an official who served in both is ranked in each)
--   committee money:   rpt_donor_rollup from PACs, committees and parties (medium name matches left out);
--                      the opposite ranks the lowest share of such money among officials raising $10,000+.
--                      The rollup holds only committee receipts for federal officials (FEC individual donors
--                      are not itemized), so a federal share would always be 100%: federal shares are per FEC
--                      two-year cycle (period = the cycle's even end year) over FEC's total receipts for the
--                      cycle (fct_federal_donor_summary); a cycle with no FEC total gets no share
--   party unity:       share of party-line votes cast with the official's own party, for the official's current
--                      chamber, from fct_party_unity_yearly (calendar year of the vote, and lifetime = all
--                      years). Needs awards_min_party_line_votes (default 20) party-line votes in the period.
--                      fct_bias_indicators party_unity_pct sums the same counts, so the lifetime figure matches
--                      the profile; the yearly figures appear with the award only.
--                      Maverick (most_party_breaks) needs at least one break
--   House passage:    most_bills_passed_house, from fct_sponsorship_outcomes: of the House bills (HB) and House
--                      joint resolutions (HJR) a member was primary sponsor of in sessions that have ended, the
--                      share the House passed, counting only decided bills (not pending, not awaiting the
--                      governor). Per calendar year of the session (a year's regular and special sessions summed)
--                      and lifetime (counts summed over all loaded sessions, not an average of shares). Needs
--                      awards_min_bills_decided (default 10) decided bills in the period. Ranked among
--                      state_house, whatever office the member holds now. Not a pair: the low end is mostly a
--                      tie at 0% (most bills die in committee), so there is no "fewest passed" award; read
--                      early years with care, only members still in office are in the data (see
--                      fct_sponsorship_outcomes)
-- Paired awards (the awards_pairs macro: attendance, party unity;
-- each pair ranks one number over one field): each end's cutoff is at most half of its ranked field
-- (floor(field / 2)) so nobody is on both lists; ties at the cutoff can add more. An official the two lists
-- would still share through a tie is dropped from both
with offices as (
    select
        official_id,
        office,
        level
    from {{ ref('dim_official') }}
),

attendance_years as (
    select
        official_id,
        chamber,
        cast(extract(year from first_vote_date) as {{ dbt.type_string() }}) as period,
        sum(votes_present) as present,
        sum(votes_recorded) as recorded
    from {{ ref('rpt_attendance') }}
    group by official_id, chamber, cast(extract(year from first_vote_date) as {{ dbt.type_string() }})
),

attendance as (
    select
        official_id,
        chamber,
        period,
        present,
        recorded
    from attendance_years
    union all
    select
        official_id,
        chamber,
        'lifetime' as period,
        sum(present) as present,
        sum(recorded) as recorded
    from attendance_years
    group by official_id, chamber
),

attendance_rates as (
    select
        a.official_id,
        -- the chamber the votes were cast in, not the official's current office: a senator's House years are
        -- ranked among House members (the same rule as party unity)
        a.chamber as office,
        a.period,
        round(100.0 * a.present / a.recorded, 1) as metric,
        a.recorded as sample_size
    from attendance as a
    inner join offices as o on a.official_id = o.official_id
    where a.recorded >= 100
),

money_years as (
    select
        official_id,
        cast(transaction_year as {{ dbt.type_string() }}) as period,
        sum(
            case when donor_class in ('pac', 'committee', 'candidate committee', 'party') then total_amount else 0 end
        ) as committee_money,
        sum(total_amount) as all_money
    from {{ ref('rpt_donor_rollup') }}
    where match_confidence <> 'medium'
    group by official_id, cast(transaction_year as {{ dbt.type_string() }})
),

money as (
    select
        official_id,
        period,
        committee_money,
        all_money
    from money_years
    union all
    select
        official_id,
        'lifetime' as period,
        sum(committee_money) as committee_money,
        sum(all_money) as all_money
    from money_years
    group by official_id
),

money_with_office as (
    select
        m.official_id,
        o.office,
        o.level,
        m.period,
        m.committee_money,
        m.all_money
    from money as m
    inner join offices as o on m.official_id = o.official_id
),

federal_committee_cycles as (
    select
        official_id,
        cast(election_cycle as {{ dbt.type_string() }}) as period,
        sum(
            case when donor_class in ('pac', 'committee', 'candidate committee', 'party') then total_amount else 0 end
        ) as committee_money
    from {{ ref('rpt_donor_rollup') }}
    where level = 'federal' and match_confidence <> 'medium'
    group by official_id, cast(election_cycle as {{ dbt.type_string() }})
),

federal_share_cycles as (
    -- the denominator is FEC's own total receipts for the cycle (individuals, PACs, parties, the candidate);
    -- a member with an FEC total but no itemized committee receipts has a committee share of 0
    select
        t.official_id,
        cast(t.cycle as {{ dbt.type_string() }}) as period,
        coalesce(c.committee_money, 0) as committee_money,
        t.total as all_money
    from {{ ref('fct_federal_donor_summary') }} as t
    left join federal_committee_cycles as c
        on
            t.official_id = c.official_id
            and cast(t.cycle as {{ dbt.type_string() }}) = c.period
    where t.aggregate_kind = 'cycle total' and t.bucket = 'total receipts' and t.total > 0
),

federal_share as (
    select
        official_id,
        period,
        committee_money,
        all_money
    from federal_share_cycles
    union all
    select
        official_id,
        'lifetime' as period,
        sum(committee_money) as committee_money,
        sum(all_money) as all_money
    from federal_share_cycles
    group by official_id
),

share_money as (
    -- state and local officials keep the calendar-year rollup figures; federal officials use FEC cycle figures
    select
        official_id,
        office,
        period,
        case when period = 'lifetime' then 'lifetime' else 'year' end as period_kind,
        committee_money,
        all_money
    from money_with_office
    where level <> 'federal'
    union all
    select
        f.official_id,
        o.office,
        f.period,
        case when f.period = 'lifetime' then 'lifetime' else 'fec_cycle' end as period_kind,
        f.committee_money,
        f.all_money
    from federal_share as f
    inner join offices as o on f.official_id = o.official_id
    where o.level = 'federal'
),

unity_counts as (
    -- the official's own chamber only (a senator's earlier House votes don't count for the Senate ranking)
    select
        y.official_id,
        o.office,
        y.vote_year,
        y.party_line_votes,
        y.with_party_votes
    from {{ ref('fct_party_unity_yearly') }} as y
    inner join offices as o on y.official_id = o.official_id and y.chamber = o.office
),

unity_totals as (
    select
        official_id,
        office,
        cast(vote_year as {{ dbt.type_string() }}) as period,
        party_line_votes,
        with_party_votes
    from unity_counts
    where vote_year is not null
    union all
    -- lifetime sums every year (and undated votes), the same sum as fct_bias_indicators party_unity_pct
    select
        official_id,
        office,
        'lifetime' as period,
        sum(party_line_votes) as party_line_votes,
        sum(with_party_votes) as with_party_votes
    from unity_counts
    group by official_id, office
),

unity as (
    select
        official_id,
        office,
        period,
        round(100.0 * with_party_votes / party_line_votes, 1) as metric,
        party_line_votes as sample_size,
        party_line_votes - with_party_votes as party_breaks,
        -- the unrounded share ranks the party awards; the rounded metric is only displayed (rounding made fake ties)
        100.0 * with_party_votes / party_line_votes as unity_exact,
        -- the whole ranked field, before Maverick drops the officials with no break
        count(*) over (partition by office, period) as field_size
    from unity_totals
    where party_line_votes >= {{ var('awards_min_party_line_votes') }}
),

house_passage_totals as (
    -- sessions that are still open are left out: their bills are undecided or the counts are partial
    select
        official_id,
        cast(session_year as {{ dbt.type_string() }}) as period,
        sum(bills_decided) as bills_decided,
        sum(bills_passed_house) as bills_passed_house
    from {{ ref('fct_sponsorship_outcomes') }}
    where is_session_over
    group by official_id, cast(session_year as {{ dbt.type_string() }})
    union all
    select
        official_id,
        'lifetime' as period,
        sum(bills_decided) as bills_decided,
        sum(bills_passed_house) as bills_passed_house
    from {{ ref('fct_sponsorship_outcomes') }}
    where is_session_over
    group by official_id
),

house_passage as (
    select
        official_id,
        -- the chamber the bills were introduced in, not the member's current office (like attendance)
        'state_house' as office,
        period,
        round(100.0 * bills_passed_house / bills_decided, 1) as metric,
        bills_decided as sample_size,
        -- the unrounded share ranks (rounding made fake ties)
        100.0 * bills_passed_house / bills_decided as share_exact
    from house_passage_totals
    where bills_decided >= {{ var('awards_min_bills_decided') }}
),

measures as (
    select
        'lowest_attendance' as award,
        official_id,
        office,
        period,
        case when period = 'lifetime' then 'lifetime' else 'year' end as period_kind,
        metric,
        sample_size,
        metric as sort_key,
        cast(null as {{ dbt.type_bigint() }}) as field_size
    from attendance_rates
    union all
    select
        'highest_attendance' as award,
        official_id,
        office,
        period,
        case when period = 'lifetime' then 'lifetime' else 'year' end as period_kind,
        metric,
        sample_size,
        -metric as sort_key,
        cast(null as {{ dbt.type_bigint() }}) as field_size
    from attendance_rates
    union all
    select
        'most_committee_money' as award,
        official_id,
        office,
        period,
        case when period = 'lifetime' then 'lifetime' else 'year' end as period_kind,
        committee_money as metric,
        all_money as sample_size,
        -committee_money as sort_key,
        cast(null as {{ dbt.type_bigint() }}) as field_size
    from money_with_office
    where committee_money > 0
    union all
    select
        'least_committee_money_share' as award,
        official_id,
        office,
        period,
        period_kind,
        round(100.0 * committee_money / all_money, 1) as metric,
        all_money as sample_size,
        100.0 * committee_money / all_money as sort_key,
        cast(null as {{ dbt.type_bigint() }}) as field_size
    from share_money
    where all_money >= 10000
    union all
    select
        'most_party_breaks' as award,
        official_id,
        office,
        period,
        case when period = 'lifetime' then 'lifetime' else 'year' end as period_kind,
        metric,
        sample_size,
        unity_exact as sort_key,
        field_size
    from unity
    -- breaking with the party needs at least one break: 100.0% unity is not a Maverick
    where party_breaks > 0
    union all
    select
        'most_party_loyal' as award,
        official_id,
        office,
        period,
        case when period = 'lifetime' then 'lifetime' else 'year' end as period_kind,
        metric,
        sample_size,
        -unity_exact as sort_key,
        field_size
    from unity
    union all
    select
        'most_bills_passed_house' as award,
        official_id,
        office,
        period,
        case when period = 'lifetime' then 'lifetime' else 'year' end as period_kind,
        metric,
        sample_size,
        -share_exact as sort_key,
        cast(null as {{ dbt.type_bigint() }}) as field_size
    from house_passage
),

ranked as (
    select
        award,
        official_id,
        office,
        period,
        period_kind,
        metric,
        sample_size,
        rank() over (partition by award, office, period order by sort_key) as award_rank,
        -- party awards: the whole ranked field (Maverick drops no-break officials from its list, not the field)
        coalesce(field_size, count(*) over (partition by award, office, period)) as group_size
    from measures
),

thresholds_by_award as (
    -- per-award cutoff from the awards_threshold var (dbt_project.yml); awards not listed use its default
    select
        award,
        office,
        period,
        period_kind,
        official_id,
        metric,
        sample_size,
        award_rank,
        group_size,
        {%- set cutoffs = mogov.awards_thresholds() %}
        {%- set own = cutoffs.items() | rejectattr(0, 'equalto', 'default') | list %}
        {#- a case needs at least one when, so with no per-award cutoffs the default stands alone #}
        {% if own | length > 0 -%}
        case
            {%- for award_name, cutoff in own %}
            when award = '{{ award_name }}' then {{ cutoff }}
            {%- endfor %}
            else {{ cutoffs['default'] }}
        end
        {%- else -%}
            {{ cutoffs['default'] }}
        {%- endif %} as base_threshold
    from ranked
    -- a ranking needs a field: single-seat offices (governor) and thin years are left out entirely, which is
    -- also why they neither add to nor break a streak
    where group_size >= {{ var('awards_min_field_size') }}
),

thresholds as (
    -- the two ends of a pair (see the awards_pairs macro) rank one number over one field, so each end's
    -- cutoff is at most half of that field: with a field of 6 and a cutoff of 5, nobody could sit in both top-5
    -- lists. Ties at the cut
    -- can still put one official in both; such an official is dropped from both (sits in the middle), see
    -- `contested`
    select
        award,
        office,
        period,
        period_kind,
        official_id,
        metric,
        sample_size,
        award_rank,
        group_size,
        {{ mogov.award_pair_expr('award') }} as pair_key,
        case
            when {{ mogov.award_pair_expr('award') }} is not null
                then least(base_threshold, cast(floor(group_size / 2.0) as {{ dbt.type_bigint() }}))
            else base_threshold
        end as threshold
    from thresholds_by_award
),

contested as (
    select
        award,
        office,
        period,
        period_kind,
        official_id,
        metric,
        sample_size,
        award_rank,
        group_size,
        threshold,
        -- both ends of a pair would take this official for this office and period
        coalesce(
            pair_key is not null
            and sum(case when award_rank <= threshold then 1 else 0 end)
                over (partition by pair_key, office, period, official_id)
            > 1,
            false
        ) as in_both_pair_lists
    from thresholds
),

yearly as (
    -- a year only has a row here if the official was ranked for this award that year. Office tenure is never
    -- checked: "not in office", "not eligible for the measure" (e.g. under $10,000 raised, under 100 recorded
    -- votes) and "field too thin" all show up as no row, and all are skipped the same way
    select
        award,
        office,
        period,
        official_id,
        case when award_rank <= threshold and not in_both_pair_lists then 1 else 0 end as qualifies,
        -- failed years so far (ranked but outside the threshold); each one starts a new run of qualifying years
        sum(case when award_rank <= threshold and not in_both_pair_lists then 0 else 1 end) over (
            partition by award, office, official_id
            order by period
            rows between unbounded preceding and current row
        ) as failures_so_far
    from contested
    where period <> 'lifetime'
),

streaks as (
    select
        award,
        office,
        period,
        official_id,
        qualifies,
        sum(qualifies) over (
            partition by award, office, official_id, failures_so_far
            order by period
            rows between unbounded preceding and current row
        ) as streak_years
    from yearly
)

select
    cast(t.award as {{ dbt.type_string() }}) as award,
    cast(t.office as {{ dbt.type_string() }}) as office,
    cast(t.period as {{ dbt.type_string() }}) as period,
    -- what the period is: a calendar 'year', a two-year 'fec_cycle' (federal money share, named by the even end
    -- year) or 'lifetime' (all loaded years)
    cast(t.period_kind as {{ dbt.type_string() }}) as period_kind,
    cast(t.award_rank as {{ dbt.type_bigint() }}) as award_rank,
    cast(t.official_id as {{ dbt.type_string() }}) as official_id,
    cast(t.metric as {{ dbt.type_numeric() }}) as metric,
    cast(t.sample_size as {{ dbt.type_numeric() }}) as sample_size,
    cast(t.group_size as {{ dbt.type_bigint() }}) as group_size,
    -- null for lifetime rows: only yearly periods make a streak
    cast(s.streak_years as {{ dbt.type_bigint() }}) as streak_years
from contested as t
left join streaks as s
    on
        t.award = s.award
        and t.office = s.office
        and t.period = s.period
        and t.official_id = s.official_id
where t.award_rank <= t.threshold and not t.in_both_pair_lists
