{{ config(enabled=var('cl_case_bulk', false)) }}
-- Sanity check on int_courtlistener__bulk_case_matches: no Missouri state judge is credited with more than 350 cases
-- in one year (max 227 on current data; the Court of Appeals decides about 600 to 1,800 opinions a year with three
-- judges each, the Supreme Court about 100). More means a surname match with no start date or with a wrong one
-- (an official credited with a predecessor's or a namesake's cases, #847).
select
    m.official_id,
    extract(year from c.date_filed) as filed_year,
    count(*) as cases
from {{ ref('int_courtlistener__bulk_case_matches') }} as m
inner join {{ ref('int_courtlistener__mo_cases') }} as c on m.cluster_id = c.cluster_id
where m.role = 'judge' and m.official_id like 'mojudge:%'
group by m.official_id, extract(year from c.date_filed)
having count(*) > 350
