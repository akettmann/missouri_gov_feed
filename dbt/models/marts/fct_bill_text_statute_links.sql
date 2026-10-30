-- Which RSMo sections each House bill text version would repeal, amend or enact, read from the enacting title and
-- Section A of the bill text PDF (int_mo_house__bill_text_statute_refs). Unlike fct_bill_statute_links, which comes
-- from the Revisor history notes and so only has bills that became law, this covers every bill version whose text the
-- mo_house_pdf loader has read, pending and failed bills included, one row per (text version, bill, section). Empty
-- until that loader has run.
-- link_source is "bill_text" here and "revisor_history" in fct_bill_statute_links, so the two can be stacked.
-- change uses the words of the Revisor mart: a section the version both repeals and enacts (the usual "repeal and
-- enact in lieu thereof") or amends is "amended"; repealed only is "repealed"; enacted only is "enacted" (a new
-- section). A version is each lr_number (0474H.01I is the introduced text, 5057S.04T the truly agreed one): bills
-- are rewritten as they move, so use version_code T (truly agreed) or the latest lr_number for what a bill ended up
-- doing. A text with no RSMo section (appropriations, joint resolutions amending the Constitution, land
-- conveyances) has no row.
with refs as (
    select
        t.session_code,
        t.bill,
        t.document_url,
        t.lr_number,
        t.version_code,
        t.section_id,
        max(case when t.action = 'repeal' then 1 else 0 end) as repeals,
        max(case when t.action = 'enact' then 1 else 0 end) as enacts,
        max(case when t.action = 'amend' then 1 else 0 end) as amends,
        cast(min(t.supp_year) as {{ dbt.type_int() }}) as supp_year,
        max(case when t.from_range then 1 else 0 end) = 1 as from_range,
        max(case when t.in_statutes then 1 else 0 end) = 1 as in_statutes
    from {{ ref('int_mo_house__bill_text_statute_refs') }} as t
    group by t.session_code, t.bill, t.document_url, t.lr_number, t.version_code, t.section_id
)

select
    session_code,
    bill,
    document_url,
    lr_number,
    version_code,
    section_id,
    case
        when amends = 1 or (repeals = 1 and enacts = 1) then 'amended'
        when repeals = 1 then 'repealed'
        else 'enacted'
    end as change,
    'bill_text' as link_source,
    supp_year,
    from_range,
    in_statutes
from refs
