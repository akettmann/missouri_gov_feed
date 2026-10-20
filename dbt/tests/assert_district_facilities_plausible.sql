-- Sanity check: areas holding implausibly many EPA FRS facilities. In October 2026 the most in one state house
-- district was 1,429 and in any area 11,089 (a U.S. House district), so more than 5,000 in a house district or
-- 40,000 anywhere means boundaries were joined twice or coordinates collapsed onto one point.
select
    district_id,
    count(*) as facilities
from {{ ref('fct_district_facilities') }}
group by district_id
having
    count(*) > 40000
    or (district_id like 'state_house:%' and count(*) > 5000)
