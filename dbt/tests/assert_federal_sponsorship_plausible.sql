-- Sanity bounds on Missouri's federal sponsorship: no member sponsors more than 1,500 bills a Congress (the record is
-- a few hundred), a law number looks like "<congress>-<n>" and its congress is the bill's own, and a member is never
-- both sponsor and cosponsor of one bill.
select
    bioguide_id,
    congress,
    cast(null as varchar) as bill_id,
    'too many sponsored bills' as problem
from {{ ref('fct_federal_sponsorship') }}
where role = 'sponsor'
group by bioguide_id, congress
having count(*) > 1500
union all
select
    bioguide_id,
    congress,
    bill_id,
    'law number does not match the bill''s congress' as problem
from {{ ref('fct_federal_sponsorship') }}
where
    became_law
    and (
        public_law_number is null
        or public_law_number not like {{ dbt.safe_cast('congress', dbt.type_string()) }} || '-%'
    )
union all
select
    bioguide_id,
    congress,
    bill_id,
    'sponsor and cosponsor of the same bill' as problem
from {{ ref('fct_federal_sponsorship') }}
group by bioguide_id, congress, bill_id
having count(distinct role) > 1
