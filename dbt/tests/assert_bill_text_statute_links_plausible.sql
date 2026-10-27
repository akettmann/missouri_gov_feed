-- Sanity check on the statute links read from House bill text (fct_bill_text_statute_links): every section id has the
-- RSMo shape (the pattern assert_statute_section_ids_wellformed checks on fct_statute_sections), and no single
-- bill text version names more than 400 sections. The largest real omnibus in the 2017-2026 House texts names far
-- fewer; more means the parser read a numbered list or a range expanded across a chapter that should not be.
select
    'section ' || section_id as what,
    document_url
from {{ ref('fct_bill_text_statute_links') }}
where not {{ mogov.regex_matches('section_id', '^[0-9]+[A-Z]?\\.[0-9]+[A-Z]?(-[0-9]+[A-Z]?)?$') }}

union all

select
    'sections in ' || bill || ' (' || lr_number || ')' as what,
    document_url
from {{ ref('fct_bill_text_statute_links') }}
group by bill, lr_number, document_url
having count(*) > 400
