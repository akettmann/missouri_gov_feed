-- The committees (and subcommittees) that handled each federal bill a Missouri member of Congress sponsored or
-- cosponsored, with how far the bill got in each: one row per (member, bill, role, committee), the grain of
-- fct_federal_sponsorship times the committees a bill was referred to. Answers "which committees decide the bills this
-- official puts their name on". A subcommittee is its own row (is_subcommittee, parent_system_code); a bill referred to
-- a subcommittee also has a row for its parent. The dates are the earliest of each step in that committee, null when
-- the step never happened (or was never dated: Congress.gov lists a few "Unknown" and undated activities, which are
-- not counted as any step).
with steps as (
    select
        bill_id,
        position,
        subposition,
        min(case when activity_normalized = 'referred to' then activity_date end) as referred_date,
        min(case when activity_normalized like 'hearings by%' then activity_date end) as hearing_date,
        min(case when activity_normalized = 'markup by' then activity_date end) as markup_date,
        min(
            case
                when activity_normalized in ('reported by', 'reported original measure') then activity_date
            end
        ) as reported_date,
        min(case when activity_normalized = 'discharged from' then activity_date end) as discharged_date
    from {{ ref('stg_govinfo_billstatus__committee_activities') }}
    group by bill_id, position, subposition
)

select
    s.official_id,
    s.bioguide_id,
    s.role,
    s.bill_id,
    s.congress,
    c.system_code as committee_system_code,
    c.name as committee_name,
    c.chamber as committee_chamber,
    c.is_subcommittee,
    c.parent_system_code,
    st.referred_date,
    st.hearing_date,
    st.markup_date,
    st.reported_date,
    st.discharged_date,
    c.source_url
from {{ ref('fct_federal_sponsorship') }} as s
inner join {{ ref('stg_govinfo_billstatus__committees') }} as c on s.bill_id = c.bill_id
left join steps as st
    on
        c.bill_id = st.bill_id
        and c.position = st.position
        and c.subposition is not distinct from st.subposition
