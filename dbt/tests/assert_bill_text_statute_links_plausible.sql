-- Sanity check on the statute links read from House bill text (fct_bill_text_statute_links): no single bill text
-- version names more than 150 sections. The largest real omnibus in the 2017-2026 House texts names far fewer; more
-- means the parser read a numbered list or a range expanded across a chapter that should not be.
{{ config(severity='warn') }}

select
    'sections in ' || bill || ' (' || lr_number || ')' as what,
    document_url
from {{ ref('fct_bill_text_statute_links') }}
group by bill, lr_number, document_url
having count(*) > 150
