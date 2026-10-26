-- Sanity check: RSMo sections printed with more than 4 versions at once, and bills that the Revisor's history notes
-- credit with changing more than 1,500 sections. Through 2026 a section has at most 2 versions side by side (one
-- in force, one not yet effective, e.g. 27.117), and the biggest bill is 1975 HB 398 (669 sections, a
-- reorganization). More means the chapter pages listed versions twice or the citation parser split one act into
-- many bills. Bills are counted per session_code: a regular-session HB 1 and an extraordinary-session HB 1 of the
-- same year are different bills.
select
    'versions of ' || section_id as what,
    count(*) as n
from {{ ref('fct_statute_sections') }}
where status in ('in force', 'not yet effective', 'historical')
group by section_id
having count(*) > 4

union all

select
    'sections changed by ' || bill || ' (session ' || session_code || ')' as what,
    count(distinct section_id) as n
from {{ ref('fct_bill_statute_links') }}
group by bill, session_code
having count(distinct section_id) > 1500
