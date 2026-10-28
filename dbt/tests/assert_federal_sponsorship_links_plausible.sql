-- Sanity bounds on the committees and subjects of Missouri members' federal bills: a bill is not referred to more than
-- 30 committees (the 118th's record is 27, counting subcommittees) or tagged with more than 500 subject terms (record
-- 249); a committee code starts with its chamber (h House, s Senate, j Joint); and a committee never reports a bill
-- before it was referred to it.
select
    bill_id,
    cast(null as varchar) as committee_system_code,
    'too many committees on one bill' as problem
from {{ ref('fct_federal_sponsorship_committees') }}
where role = 'sponsor'
group by bill_id
having count(*) > 30
union all
select
    bill_id,
    cast(null as varchar) as committee_system_code,
    'too many subjects on one bill' as problem
from {{ ref('fct_federal_sponsorship_subjects') }}
where role = 'sponsor'
group by bill_id
having count(*) > 500
union all
select
    bill_id,
    committee_system_code,
    'committee code does not match its chamber' as problem
from {{ ref('fct_federal_sponsorship_committees') }}
where
    substring(committee_system_code, 1, 1)
    <> case committee_chamber when 'House' then 'h' when 'Senate' then 's' else 'j' end
union all
select
    bill_id,
    committee_system_code,
    'reported before referred' as problem
from {{ ref('fct_federal_sponsorship_committees') }}
where reported_date < referred_date
