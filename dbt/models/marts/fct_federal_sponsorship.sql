-- Federal bills sponsored or cosponsored by Missouri's members of Congress (sponsor state MO in the BILLSTATUS file),
-- one row per (member, bill, role), with the bill's outcome as a fact: became_law is true when the bill's actions
-- record it becoming Public or Private Law (int_federal_bills__stage, action codes 36000/41000; law_type says which
-- and comes from the laws list). The laws list alone never makes a bill law: it can credit a law to the wrong bill
-- (119 H.R. 766 lists Public Law 119-120, which is 119 S. 766, #729). A cosponsor who withdrew is dropped.
-- official_id is set for current members (null for past ones).
with mo as (
    select
        s.bill_id,
        s.bioguide_id,
        s.full_name,
        s.party,
        s.state,
        'sponsor' as role,
        false as is_original_cosponsor
    from {{ ref('stg_govinfo_billstatus__sponsors') }} as s
    union all
    select
        c.bill_id,
        c.bioguide_id,
        c.full_name,
        c.party,
        c.state,
        'cosponsor' as role,
        c.is_original_cosponsor
    from {{ ref('stg_govinfo_billstatus__cosponsors') }} as c
    where c.sponsorship_withdrawn_date is null
),

-- A bill can carry two laws; keep the earliest by number (numerically: 118-21 before 118-100), a Public Law before a
-- Private one on a tie.
laws as (
    select
        bill_id,
        law_type,
        law_number,
        row_number() over (
            partition by bill_id
            order by law_congress, law_sequence, case when law_type = 'Public Law' then 0 else 1 end
        ) as law_rank
    from {{ ref('stg_govinfo_billstatus__laws') }}
)

select
    o.official_id,
    mo.bioguide_id,
    mo.full_name,
    mo.party,
    mo.role,
    mo.is_original_cosponsor,
    b.bill_id,
    b.congress,
    b.bill_type,
    b.bill_number,
    b.introduced_date,
    b.title,
    b.policy_area,
    b.latest_action_date,
    b.latest_action_text,
    l.law_type,
    l.law_number,
    st.stage = 'became_law' as became_law,
    b.legislation_url as source_url
from mo
inner join {{ ref('stg_govinfo_billstatus__bills') }} as b on mo.bill_id = b.bill_id
left join {{ ref('int_federal_bills__stage') }} as st on mo.bill_id = st.bill_id
left join laws as l on mo.bill_id = l.bill_id and l.law_rank = 1 and st.stage = 'became_law'
left join {{ ref('dim_official') }} as o on mo.bioguide_id = o.bioguide_id
where mo.state = 'MO'
