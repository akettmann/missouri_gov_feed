-- The RSMo sections each House bill text version names in its enacting title and Section A
-- (stg_mo_house__statute_refs), one row per (text version, bill, action, ordinal, section) with ranges expanded:
-- "sections 2.020 to 2.040" becomes every section of that span that fct_statute_sections has, plus both endpoints
-- (a repealed range may end at a section the Revisor no longer lists; an enacted range names sections that do not
-- exist yet). A range that crosses a chapter is not expanded: only its two endpoints are kept.
-- Within a chapter sections run in the order of the number after the point, read as an integer (140.995 is followed
-- by 140.1000, 67.646 by 67.1157), then its letter or uniform-code suffix as text. The section lists in House bill
-- titles follow that order in 1,698 of 1,699 consecutive pairs (the other is a section named twice), not a
-- decimal one.
-- bill comes from fct_bill_documents (a text version shared by combined bills gives a row per bill); a text PDF no
-- bill links has no row. in_statutes says whether fct_statute_sections has the section today: false for a section
-- the bill would enact, or one the Revisor has since moved or dropped. from_range marks a section that came from a
-- range.
with documents as (
    select distinct
        session_code,
        bill,
        document_url
    from {{ ref('fct_bill_documents') }}
    where document_kind = 'bill_text'
),

joined as (
    select
        d.session_code,
        d.bill,
        r.document_url,
        r.lr_number,
        r.version_code,
        r.action,
        r.ordinal,
        r.section_start,
        r.section_end,
        r.supp_year,
        {{ dbt.split_part('r.section_start', "'.'", 1) }} as start_chapter,
        {{ dbt.split_part('r.section_start', "'.'", 2) }} as start_tail,
        {{ dbt.split_part('r.section_end', "'.'", 1) }} as end_chapter,
        {{ dbt.split_part('r.section_end', "'.'", 2) }} as end_tail
    from {{ ref('stg_mo_house__statute_refs') }} as r
    inner join documents as d
        on r.document_url = d.document_url and r.session_code = d.session_code
),

refs as (
    select
        *,
        cast({{ mogov.regex_extract('start_tail', '^([0-9]+)') }} as {{ dbt.type_bigint() }}) as start_num,
        {{ mogov.regex_replace_all('start_tail', '^[0-9]+', '') }} as start_rest,
        cast({{ mogov.regex_extract('end_tail', '^([0-9]+)') }} as {{ dbt.type_bigint() }}) as end_num,
        {{ mogov.regex_replace_all('end_tail', '^[0-9]+', '') }} as end_rest
    from joined
),

statute_ids as (
    select distinct
        section_id,
        {{ dbt.split_part('section_id', "'.'", 1) }} as chapter,
        {{ dbt.split_part('section_id', "'.'", 2) }} as tail
    from {{ ref('fct_statute_sections') }}
),

statutes as (
    select
        section_id,
        chapter,
        cast({{ mogov.regex_extract('tail', '^([0-9]+)') }} as {{ dbt.type_bigint() }}) as tail_num,
        {{ mogov.regex_replace_all('tail', '^[0-9]+', '') }} as tail_rest
    from statute_ids
),

-- the section as written, and a range's far endpoint
named as (
    select
        session_code,
        bill,
        document_url,
        lr_number,
        version_code,
        action,
        ordinal,
        section_start,
        section_end,
        supp_year,
        section_start as section_id,
        section_end is not null as from_range
    from refs

    union all

    select
        session_code,
        bill,
        document_url,
        lr_number,
        version_code,
        action,
        ordinal,
        section_start,
        section_end,
        supp_year,
        section_end as section_id,
        true as from_range
    from refs
    where section_end is not null
),

-- the statute sections strictly inside a range that stays within one chapter
spanned as (
    select
        r.session_code,
        r.bill,
        r.document_url,
        r.lr_number,
        r.version_code,
        r.action,
        r.ordinal,
        r.section_start,
        r.section_end,
        r.supp_year,
        s.section_id,
        true as from_range
    from refs as r
    inner join statutes as s
        on
            r.section_end is not null
            and r.start_chapter = r.end_chapter
            and r.start_chapter = s.chapter
            and (r.start_num < s.tail_num or (r.start_num = s.tail_num and r.start_rest < s.tail_rest))
            and (r.end_num > s.tail_num or (r.end_num = s.tail_num and r.end_rest > s.tail_rest))
),

expanded as (
    select * from named
    union all
    select * from spanned
),

deduped as (
    select
        session_code,
        bill,
        document_url,
        lr_number,
        version_code,
        action,
        ordinal,
        section_start,
        section_end,
        section_id,
        min(supp_year) as supp_year,
        max(case when from_range then 1 else 0 end) = 1 as from_range
    from expanded
    group by
        session_code, bill, document_url, lr_number, version_code, action, ordinal,
        section_start, section_end, section_id
)

select
    e.session_code,
    e.bill,
    e.document_url,
    e.lr_number,
    e.version_code,
    e.action,
    e.ordinal,
    e.section_start,
    e.section_end,
    e.section_id,
    e.supp_year,
    e.from_range,
    s.section_id is not null as in_statutes
from deduped as e
left join (select distinct section_id from statutes) as s on e.section_id = s.section_id
