-- Every roll call a BILLSTATUS amendment action cites should exist in Voteview, keyed by (congress, chamber, session,
-- clerk roll number), for the Congresses Voteview was loaded for (observed 630 of 630 in the 118th). Voteview can lag
-- a new vote by days, so a small share of misses is allowed (2%); more means the key is wrong (e.g. joining on
-- Voteview's Congress-wide rollnumber). Also, where Voteview names a bill, it should be the bill the amendment was
-- filed to (HR2494 for 118-hamdt-180; observed 630 of 630), same 2% bound.
with cited as (
    select distinct
        congress,
        chamber,
        session_number,
        roll_number
    from {{ ref('stg_govinfo_billstatus__amendment_recorded_votes') }}
    where
        roll_number is not null
        and session_number is not null
        and congress in (select distinct r.congress from {{ ref('stg_voteview__rollcalls') }} as r)
),

misses as (
    select count(*) as n
    from cited as c
    left join {{ ref('stg_voteview__rollcalls') }} as r
        on
            c.congress = r.congress
            and c.chamber = r.chamber
            and c.session_number = r.session
            and c.roll_number = r.clerk_rollnumber
    where r.rollnumber is null
),

disagreements as (
    select count(*) as n
    from {{ ref('fct_federal_vote_amendments') }}
    where
        voteview_bill_number is not null
        and upper(replace(voteview_bill_number, ' ', ''))
        <> upper(bill_type || cast(bill_no as {{ dbt.type_string() }}))
),

totals as (
    select
        (select count(*) from cited) as cited_n,
        (select count(*) from {{ ref('fct_federal_vote_amendments') }}) as linked_n
)

select
    'cited amendment roll calls missing from Voteview' as problem,
    misses.n as n_found,
    totals.cited_n as out_of
from misses
cross join totals
where misses.n > 0.02 * totals.cited_n
union all
select
    'linked bill disagrees with Voteview bill_number' as problem,
    disagreements.n as n_found,
    totals.linked_n as out_of
from disagreements
cross join totals
where disagreements.n > 0.02 * totals.linked_n
