{{ config(severity='warn') }}

-- Agreement check (warn): for a bill that became law, the sections its truly agreed text (version T) repeals or
-- amends should mostly be the sections the Revisor's history notes credit the bill with changing (a section moved
-- to a credited number counts: see fct_bill_text_revisor_agreement). A bill whose text names three or more such
-- sections of which fewer than half are credited means the parser read the wrong sections, or the text and the act
-- diverged (a section vetoed, or an act the Revisor cites under another bill, as in a combined act). Bills the
-- Revisor has no links for (not yet in the statutes, or failed) are not checked.
select
    session_code,
    bill,
    text_sections,
    also_in_revisor_links
from {{ ref('fct_bill_text_revisor_agreement') }}
where text_sections >= 3 and also_in_revisor_links < 0.5 * text_sections
