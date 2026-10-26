-- Revised Statutes of Missouri (RSMo), one row per section version from the Revisor of Statutes: the versions listed
-- in force (text, heading, effective date, session-law history) and the repealed and transferred sections (note and
-- date only). A section can have several versions at once: is_current marks the in-force one(s) with the latest
-- effective date on the build date (two when the Revisor prints conflicting enactments side by side). When a court
-- held the newest version unconstitutional in whole or part (held_unconstitutional), the Revisor also prints the
-- version before it; is_current still points at the newest, so read the flag alongside it.
-- A version can be on both pages: listed in force (or contingent) on its chapter page and printed on the repeals page
-- with a future repeal ("Repealed L. 2026 S.B. 1233", contingent date 2099: 324.406/60569). It stays one row, the
-- listed one, flagged repeal_pending; the repeals page's copy is dropped.
{% set as_of = "cast('" ~ var('as_of_date') ~ "' as date)" if var('as_of_date', none) else 'current_date' %}

with repealed_ids as (
    select distinct section_version_id
    from {{ ref('stg_mo_revisor__repeals') }}
),

listed as (
    select
        s.section_id,
        s.bid,
        s.section_version_id,
        s.chapter,
        s.heading,
        case
            when s.is_historical then 'historical'
            when s.is_contingent then 'contingent'
            when s.effective_date > {{ as_of }} then 'not yet effective'
            else 'in force'
        end as status,
        s.effective_date,
        s.held_unconstitutional,
        cast(null as date) as ended_date,
        cast(null as {{ dbt.type_string() }}) as transferred_to,
        s.history_note,
        s.section_text,
        s.source_url,
        r.section_version_id is not null as repeal_pending
    from {{ ref('stg_mo_revisor__sections') }} as s
    left join repealed_ids as r on s.section_version_id = r.section_version_id
),

removed as (
    select
        section_id,
        bid,
        section_version_id,
        chapter,
        cast(null as {{ dbt.type_string() }}) as heading,
        change_kind as status,
        cast(null as date) as effective_date,
        false as held_unconstitutional,
        action_date as ended_date,
        transferred_to,
        note as history_note,
        cast(null as {{ dbt.type_string() }}) as section_text,
        source_url,
        false as repeal_pending
    from {{ ref('stg_mo_revisor__repeals') }} as rp
    where not exists (
        select 1 from {{ ref('stg_mo_revisor__sections') }} as s
        where s.section_version_id = rp.section_version_id
    )
),

versions as (
    select * from listed
    union all
    select * from removed
),

latest_in_force as (
    select
        section_id,
        max(effective_date) as effective_date
    from listed
    where status = 'in force'
    group by section_id
)

select
    v.section_id,
    v.bid,
    v.section_version_id,
    v.chapter,
    c.chapter_name,
    c.title_numeral,
    c.title_name,
    v.heading,
    v.status,
    coalesce(v.status = 'in force' and v.effective_date = l.effective_date, false) as is_current,
    v.effective_date,
    v.held_unconstitutional,
    v.ended_date,
    v.transferred_to,
    v.history_note,
    v.section_text,
    v.repeal_pending,
    v.source_url
from versions as v
left join {{ ref('stg_mo_revisor__chapters') }} as c on v.chapter = c.chapter
left join latest_in_force as l on v.section_id = l.section_id
