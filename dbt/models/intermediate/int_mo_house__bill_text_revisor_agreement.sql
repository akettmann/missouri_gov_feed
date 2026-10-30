-- How well the sections a bill's truly agreed text (version T) repeals or amends match the sections the Revisor's
-- history notes credit that bill with changing (fct_bill_statute_links). One row per bill that became law in the
-- Revisor's notes and whose T text names at least one such section; assert_bill_text_repeals_agree_with_revisor_links
-- warns on the low ones. Bills the Revisor has no links for (not yet in the statutes, or failed) have no row.
-- A bill that renumbers sections (HB 3279, 2026: 620.580-620.592 moved to 173.4000-173.4012) is credited by the
-- Revisor only with the new numbers, because a moved section's repeal note says "(Transferred 2026; now 173.4000)"
-- with no bill. A repealed section the Revisor lists as transferred to a section credited to the same bill therefore
-- counts as agreeing (via_transfer). The transfer is read from the Revisor's repeal list, not guessed from the text.
with text_sections as (
    select distinct
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
),

-- the section a section moved to, by the Revisor's repeals-and-transfers list
moved as (
    select distinct
        section_id,
        transferred_to
    from {{ ref('stg_mo_revisor__repeals') }}
    where change_kind = 'transferred' and transferred_to is not null
),

matched as (
    select
        t.session_code,
        t.bill,
        t.section_id,
        max(case when r.section_id is not null then 1 else 0 end) as direct_link,
        max(case when moved_link.section_id is not null then 1 else 0 end) as via_transfer
    from text_sections as t
    left join revisor as r
        on t.session_code = r.session_code and t.bill = r.bill and t.section_id = r.section_id
    left join moved as m
        on t.section_id = m.section_id
    left join revisor as moved_link
        on
            t.session_code = moved_link.session_code
            and t.bill = moved_link.bill
            and m.transferred_to = moved_link.section_id
    group by t.session_code, t.bill, t.section_id
)

select
    session_code,
    bill,
    count(*) as text_sections,
    cast(sum(direct_link) as bigint) as linked_directly,
    cast(sum(case when direct_link = 0 and via_transfer = 1 then 1 else 0 end) as bigint) as linked_via_transfer,
    cast(sum(case when direct_link = 1 or via_transfer = 1 then 1 else 0 end) as bigint) as also_in_revisor_links
from matched as m
where
    exists (
        select 1
        from revisor as any_link
        where any_link.session_code = m.session_code and any_link.bill = m.bill
    )
group by session_code, bill
