-- Sanity checks on the per-member federal committee and subject counts: a step count never exceeds the bills, a
-- member's bills in one committee or subject never exceed the bills they put their name on in that Congress and role,
-- and no member has an implausible number of bills in one committee or subject in a Congress (3,000 is far beyond
-- any member's cosponsorships).
with named as (
    select
        bioguide_id,
        congress,
        role,
        count(distinct bill_id) as named_bills
    from {{ ref('fct_federal_sponsorship') }}
    group by bioguide_id, congress, role
)

select
    c.bioguide_id,
    c.congress,
    c.role,
    c.committee_system_code as detail,
    'committee step count exceeds bills, or bills exceed the bills named' as problem
from {{ ref('fct_federal_member_committees') }} as c
inner join named as n on c.bioguide_id = n.bioguide_id and c.congress = n.congress and c.role = n.role
where
    c.bills > n.named_bills
    or c.bills_with_hearing > c.bills
    or c.bills_marked_up > c.bills
    or c.bills_reported > c.bills
    or c.bills_discharged > c.bills
    or c.bills > 3000
union all
select
    s.bioguide_id,
    s.congress,
    s.role,
    s.subject as detail,
    'subject step count exceeds bills, or bills exceed the bills named' as problem
from {{ ref('fct_federal_member_subjects') }} as s
inner join named as n on s.bioguide_id = n.bioguide_id and s.congress = n.congress and s.role = n.role
where
    s.bills > n.named_bills
    or s.bills_marked_up > s.bills
    or s.bills_reported > s.bills
    or s.bills_became_law > s.bills
    or s.bills > 3000
