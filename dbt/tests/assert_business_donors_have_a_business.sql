-- fct_jurisdiction_business_donors rows belong to a row of fct_jurisdiction_businesses, and that row is flagged
-- is_donor (a composite foreign key, which the relationships test cannot express), and every donor-flagged business
-- has at least one donor row.
select
    d.official_id,
    d.registry_id
from {{ ref('fct_jurisdiction_business_donors') }} as d
left join {{ ref('fct_jurisdiction_businesses') }} as b
    on d.official_id = b.official_id and d.registry_id = b.registry_id
where b.registry_id is null or not b.is_donor

union all

select
    b.official_id,
    b.registry_id
from {{ ref('fct_jurisdiction_businesses') }} as b
where
    b.is_donor
    and not exists (
        select 1
        from {{ ref('fct_jurisdiction_business_donors') }} as d
        where d.official_id = b.official_id and d.registry_id = b.registry_id
    )
