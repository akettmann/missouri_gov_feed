{#
  Rows of fct_jurisdiction_businesses that break what the frontend's district EPA site pages assume
  (frontend/src/lib/exports/districtSites.ts, #134): a page is keyed by district but written for one official, so
  district <-> official is 1:1, and a facility appears once per district. One row per offending key.
  `relation` is any relation with official_id, district_id and registry_id.
#}
{% macro site_page_violations(relation) %}
select
    'district has several officials' as problem,
    district_id as key_value,
    count(distinct official_id) as n
from {{ relation }}
group by district_id
having count(distinct official_id) > 1

union all

select
    'official has several districts' as problem,
    official_id as key_value,
    count(distinct district_id) as n
from {{ relation }}
group by official_id
having count(distinct district_id) > 1

union all

select
    'facility repeated in a district' as problem,
    district_id || ' / ' || registry_id as key_value,
    count(*) as n
from {{ relation }}
group by district_id, registry_id
having count(*) > 1
{% endmacro %}
