-- A facility lies in at most one current area of each type (one house district, one county...). Two means
-- overlapping boundaries, such as two vintages of a layer both marked current.
select
    f.registry_id,
    d.district_type,
    count(*) as areas
from {{ ref('fct_district_facilities') }} as f
inner join {{ ref('dim_district') }} as d on f.district_id = d.district_id
group by f.registry_id, d.district_type
having count(*) > 1
