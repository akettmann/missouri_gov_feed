-- Sanity check: more holders of an office in one year than its seats plus a few mid-year replacements means
-- a term is double-counted or a roster was misread. Seats: MO House 163, MO Senate 34, U.S. House 8 (since
-- 2023; 9 before), U.S. Senate 2. Federal judgeships in Missouri, with senior judges, have never neared 60.
select
    year,
    office,
    count(*) as holders
from {{ ref('rpt_officeholders_by_year') }}
group by year, office
having
    count(*) > case office
        when 'state_house' then 175
        when 'state_senate' then 40
        when 'us_house' then 12
        when 'us_senate' then 4
        when 'us_district_court' then 60
        when 'us_court_of_appeals' then 15
        else 1000
    end
