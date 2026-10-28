-- Sanity checks for the statute marts the site pages read. A row here is a statute page that would be wrong:
--  - a section version with more than 100 footnotes (the most seen is 39),
--  - a chapter with more than 2,000 section versions (the largest, chapter 400, has about 700; more means the
--    chapter pages were listed twice),
--  - rpt_statute_chapters not adding up to fct_statute_sections: every version must be counted in exactly one
--    status column of exactly one chapter.
select
    'footnotes on ' || section_version_id as what,
    count(*) as n
from {{ ref('fct_statute_section_footnotes') }}
group by section_version_id
having count(*) > 100

union all

select
    'section versions in chapter ' || chapter as what,
    count(*) as n
from {{ ref('fct_statute_sections') }}
group by chapter
having count(*) > 2000

union all

select
    'rpt_statute_chapters section_versions total' as what,
    sum(section_versions) as n
from {{ ref('rpt_statute_chapters') }}
having
    sum(section_versions) != (select count(*) from {{ ref('fct_statute_sections') }})
    or sum(
        in_force_versions + not_yet_effective_versions + contingent_versions
        + historical_versions + repealed_versions + transferred_versions
    ) != sum(section_versions)
