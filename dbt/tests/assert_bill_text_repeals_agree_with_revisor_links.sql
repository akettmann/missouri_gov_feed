{{ config(severity='warn') }}

-- Agreement check (warn): for a bill that became law, the sections its truly agreed text (version T) repeals or
-- amends should mostly be the sections the Revisor's history notes credit the bill with changing. A bill whose
-- text names three or more such sections of which fewer than half are in fct_bill_statute_links means the parser
-- read the wrong sections, or the text and the act diverged (a section vetoed, or an act the Revisor cites under
-- another bill, as in a combined act). Bills the Revisor has no links for (not yet in the statutes, or failed)
-- are not checked.
with text_sections as (
    select
        session_code,
        bill,
        section_id
    from {{ ref('fct_bill_text_statute_links') }}
    where version_code = 'T' and change in ('amended', 'repealed')
),

revisor as (
    select distinct
        session_code,
        bill,
        section_id
    from {{ ref('fct_bill_statute_links') }}
)

select
    t.session_code,
    t.bill,
    count(*) as text_sections,
    count(r.section_id) as also_in_revisor_links
from text_sections as t
left join revisor as r
    on t.session_code = r.session_code and t.bill = r.bill and t.section_id = r.section_id
where
    exists (
        select 1
        from revisor as any_link
        where any_link.session_code = t.session_code and any_link.bill = t.bill
    )
group by t.session_code, t.bill
having count(*) >= 3 and count(r.section_id) < 0.5 * count(*)
