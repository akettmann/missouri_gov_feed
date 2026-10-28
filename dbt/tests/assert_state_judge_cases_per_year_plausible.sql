{{ config(enabled=var('cl_case_bulk', false)) }}
-- Sanity check on int_courtlistener__bulk_case_matches: no Missouri state judge is credited with more than 300 cases
-- in one year (max 210 on current data, Ahuja in 2010, and 126 for the judges dated from payroll; the Court of Appeals
-- decides about 600 to 1,800 opinions a year with three judges each, the Supreme Court about 100). More means a surname
-- match with no start date or with a wrong one (an official credited with a predecessor's or a namesake's cases, #847).
-- It is a coarse net: a namesake merged into a judge's year of ordinary volume (Dowd's 227 before the namesake guard)
-- is within the range established judges reach, so the unit tests carry that case, not this threshold.
select
    m.official_id,
    extract(year from c.date_filed) as filed_year,
    count(*) as cases
from {{ ref('int_courtlistener__bulk_case_matches') }} as m
inner join {{ ref('int_courtlistener__mo_cases') }} as c on m.cluster_id = c.cluster_id
where m.role = 'judge' and m.official_id like 'mojudge:%'
group by m.official_id, extract(year from c.date_filed)
having count(*) > 300
