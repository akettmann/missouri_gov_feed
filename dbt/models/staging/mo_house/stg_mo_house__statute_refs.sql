-- The RSMo sections each House bill text version repeals, amends or enacts, as the mo_house_pdf loader read them from
-- the enacting title ("To repeal sections 1.010 and 2.020 to 2.040, RSMo, ...") and Section A ("... to be known as
-- sections ..."): one row per section or range as written, in the order written within its action (ordinal).
-- A range ("2.020 to 2.040") is one row with section_end set; int_mo_house__bill_text_statute_refs expands it.
-- supp_year is the year of "RSMo Supp. 2023" when the section is cited from a supplement. clause_text is the
-- title or Section A text the row came from, with control characters removed. Bill text versions only; empty
-- until `mogov load mo_house_pdf` has run. Join to fct_bill_documents on document_url for the bill (the loader
-- does not know it, and a Senate act list file holds many).
select
    trim(url) as document_url,
    session_code,
    file_name,
    lr_number,
    version_code,
    ordinal,
    action,
    trim(section_start) as section_start,
    trim(section_end) as section_end,
    supp_year,
    trim({{ mogov.clean_pdf_text('clause') }}) as clause_text
from {{ source('mo_house', 'pdf_statute_refs') }}
