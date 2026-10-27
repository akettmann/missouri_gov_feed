-- Federal bills sponsored or cosponsored by Missouri's members of Congress (sponsor state MO in the BILLSTATUS file),
-- one row per (member, bill, role), with the bill's outcome as a fact: became_law is true when the bill carries a
-- Public Law number. A cosponsor who withdrew is dropped. official_id is set for current members (null for past ones).
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

laws as (
    select
        bill_id,
        min(law_number) as public_law_number
    from {{ ref('stg_govinfo_billstatus__laws') }}
    group by bill_id
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
    l.public_law_number,
    l.bill_id is not null as became_law,
    b.legislation_url as source_url
from mo
inner join {{ ref('stg_govinfo_billstatus__bills') }} as b on mo.bill_id = b.bill_id
left join laws as l on mo.bill_id = l.bill_id
left join {{ ref('dim_official') }} as o on mo.bioguide_id = o.bioguide_id
where mo.state = 'MO'
