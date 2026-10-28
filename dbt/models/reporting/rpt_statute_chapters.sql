-- One row per RSMo chapter with the number of section versions in each status, for the statutes index pages. Every
-- count is of section versions (fct_statute_sections rows), so the status counts add up to section_versions and a
-- chapter's counts add up to the table's row count across chapters; sections counts distinct section numbers, and
-- sections_in_force the distinct numbers with an in-force version. Chapter and title names come from the Revisor's
-- table of contents and are null for a chapter it no longer lists (repealed chapters still have repealed sections
-- here). loaded_at is the oldest landing of any of the chapter's pages: the chapter's "as of" date.
select
    chapter,
    max(chapter_name) as chapter_name,
    max(title_numeral) as title_numeral,
    max(title_name) as title_name,
    count(*) as section_versions,
    count(distinct section_id) as sections,
    count(distinct case when status = 'in force' then section_id end) as sections_in_force,
    count(case when status = 'in force' then 1 end) as in_force_versions,
    count(case when status = 'not yet effective' then 1 end) as not_yet_effective_versions,
    count(case when status = 'contingent' then 1 end) as contingent_versions,
    count(case when status = 'historical' then 1 end) as historical_versions,
    count(case when status = 'repealed' then 1 end) as repealed_versions,
    count(case when status = 'transferred' then 1 end) as transferred_versions,
    min(loaded_at) as loaded_at
from {{ ref('fct_statute_sections') }}
group by chapter
