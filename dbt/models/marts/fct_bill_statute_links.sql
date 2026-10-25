-- Which RSMo sections each bill enacted, amended or repealed, from the Revisor's session-law history notes. These
-- cover bills that became law (the Revisor records an act once it takes effect); a pending bill's targets are in its
-- text, which isn't loaded yet. Bills from before the House XML export (2017) or from a session it lacks are linked
-- all the same: in_fct_bills says whether fct_bills has the bill.
with links as (
    select
        session_code,
        act_year as session_year,
        bill,
        section_id,
        change,
        min(act) as citation,
        count(distinct section_version_id) as section_versions
    from {{ ref('int_mo_revisor__session_law_bills') }}
    group by session_code, act_year, bill, section_id, change
)

select
    l.session_code,
    l.session_year,
    l.bill,
    l.section_id,
    l.change,
    l.citation,
    l.section_versions,
    b.bill is not null as in_fct_bills
from links as l
left join {{ ref('fct_bills') }} as b on l.session_code = b.session_code and l.bill = b.bill
