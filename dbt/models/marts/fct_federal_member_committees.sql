-- Per Missouri member of Congress, Congress, role (sponsor/cosponsor) and committee (a subcommittee is its own row):
-- how many distinct bills the member put their name on that were referred there, and how many of those the committee
-- held a hearing on, marked up, reported (or forwarded, for a subcommittee) or lost to a discharge. Rolls
-- fct_federal_sponsorship_committees (one row per member, bill, role, committee) up over bills, so a bill referred to
-- several committees counts once in each. The counts are of bills (count distinct), never of committee rows.
select
    official_id,
    bioguide_id,
    congress,
    role,
    committee_system_code,
    min(committee_name) as committee_name,
    min(committee_chamber) as committee_chamber,
    bool_or(is_subcommittee) as is_subcommittee,
    min(parent_system_code) as parent_system_code,
    count(distinct bill_id) as bills,
    count(distinct case when hearing_date is not null then bill_id end) as bills_with_hearing,
    count(distinct case when markup_date is not null then bill_id end) as bills_marked_up,
    count(distinct case when reported_date is not null then bill_id end) as bills_reported,
    count(distinct case when discharged_date is not null then bill_id end) as bills_discharged,
    min(referred_date) as first_referred_date,
    max(referred_date) as last_referred_date
from {{ ref('fct_federal_sponsorship_committees') }}
group by official_id, bioguide_id, congress, role, committee_system_code
