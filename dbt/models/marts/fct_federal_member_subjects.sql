-- Per Missouri member of Congress, Congress, role (sponsor/cosponsor) and CRS legislative subject: how many distinct
-- bills the member put their name on that carry the subject, and how far those bills got. Rolls
-- fct_federal_sponsorship_subjects (one row per member, bill, role, subject) up over bills. A subject belongs to the
-- bill, not to one committee, so "marked up" and "reported" are bill-level: a bill counts when any committee marked it
-- up, and counts as reported when a full committee reported it (a subcommittee forwarding it to its full committee is
-- not reporting it to the chamber). Bills CRS has not tagged yet have no subject and are in no row.
with bill_steps as (
    select
        bioguide_id,
        bill_id,
        role,
        max(case when markup_date is not null then 1 else 0 end) as marked_up,
        max(case when reported_date is not null and not is_subcommittee then 1 else 0 end) as reported
    from {{ ref('fct_federal_sponsorship_committees') }}
    group by bioguide_id, bill_id, role
)

select
    sub.official_id,
    sub.bioguide_id,
    sub.congress,
    sub.role,
    sub.subject,
    count(distinct sub.bill_id) as bills,
    count(distinct case when bs.marked_up = 1 then sub.bill_id end) as bills_marked_up,
    count(distinct case when bs.reported = 1 then sub.bill_id end) as bills_reported,
    count(distinct case when sp.became_law then sub.bill_id end) as bills_became_law
from {{ ref('fct_federal_sponsorship_subjects') }} as sub
left join bill_steps as bs
    on
        sub.bioguide_id = bs.bioguide_id
        and sub.bill_id = bs.bill_id
        and sub.role = bs.role
inner join {{ ref('fct_federal_sponsorship') }} as sp
    on
        sub.bioguide_id = sp.bioguide_id
        and sub.bill_id = sp.bill_id
        and sub.role = sp.role
group by sub.official_id, sub.bioguide_id, sub.congress, sub.role, sub.subject
