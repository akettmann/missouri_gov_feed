-- Every section id on the statute links read from House bill text (fct_bill_text_statute_links) has the RSMo shape
-- (the pattern assert_statute_section_ids_wellformed checks on fct_statute_sections). A malformed id means the
-- parser read something that is not a section.
{{ config(severity='error') }}

select
    'section ' || section_id as what,
    document_url
from {{ ref('fct_bill_text_statute_links') }}
where not {{ mogov.regex_matches('section_id', '^[0-9]+[A-Z]?\.[0-9]+[A-Z]?(-[0-9]+[A-Z]?)?$') }}
