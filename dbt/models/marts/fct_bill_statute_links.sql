-- Which RSMo sections each bill enacted, amended or repealed, from the Revisor's session-law history notes. These
-- cover bills that became law (the Revisor records an act once it takes effect); a pending bill's targets are read
-- from its text in fct_bill_text_statute_links (link_source tells the two apart: 'revisor_history' here). Bills from
-- before the House XML export (2017) or from a session it lacks are linked all the same:
-- in_fct_bills says whether fct_bills has the bill.
-- A combined act ("A.L. 2023 H.B. 115 & 99") is one substitute carrying several bills: the first is the lead bill and
-- the only one that passed; the others are linked too (their subjects went into the act) with is_lead_bill false and
-- combined_into naming the lead. They never reach the governor themselves, so fct_bills shows them as failed. Use
-- is_lead_bill when asking which bills became law.
with links as (
    select
        session_code,
        act_year as session_year,
        bill,
        section_id,
        change,
        min(act) as citation,
        count(distinct section_version_id) as section_versions,
        max(case when is_lead_bill then 1 else 0 end) as lead_acts,
        min(combined_into) as combined_into
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
    l.lead_acts = 1 as is_lead_bill,
    case when l.lead_acts = 0 then l.combined_into end as combined_into,
    b.bill is not null as in_fct_bills,
    'revisor_history' as link_source
from links as l
left join {{ ref('fct_bills') }} as b on l.session_code = b.session_code and l.bill = b.bill
