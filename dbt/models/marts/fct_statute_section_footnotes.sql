-- The footnotes the Revisor prints under each RSMo section version (fct_statute_sections), one row per footnote in
-- page order: the session-law history, "Prior revisions" lines, the Revisor's court-case annotations (a section can
-- carry dozens) and notes such as "Effective 1-01-17". footnote_text is verbatim. is_history_note marks the first
-- footnote when it is the session-law history that fct_statute_sections carries as history_note. Repealed and
-- transferred sections have no footnotes (their note is history_note on fct_statute_sections).
select
    f.section_version_id,
    f.footnote_number,
    s.section_id,
    f.footnote_text,
    coalesce(f.footnote_number = 1 and f.footnote_text = s.history_note, false) as is_history_note,
    s.source_url,
    s.fetched_at,
    s.loaded_at
from {{ ref('stg_mo_revisor__section_footnotes') }} as f
inner join {{ ref('fct_statute_sections') }} as s on f.section_version_id = s.section_version_id
