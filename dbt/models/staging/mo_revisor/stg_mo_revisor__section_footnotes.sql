-- One row per footnote of an RSMo section version, in the order the Revisor's page prints them (footnote_number is
-- 1-based). The footnotes are the session-law history ("(RSMo 1939 § 645, A.L. 1957 p. 587, A.L. 2015 S.B. 239)"),
-- "Prior revisions" lines, the Revisor's court-case annotations ("(1960) An alley in a city is a highway ...") and
-- notes such as "Effective 1-01-17", up to 39 on one version. footnote_text is verbatim: the source has no HTML
-- entities, U+FFFD or filler to clean (tests/assert_statute_footnotes_are_clean_text.sql keeps it so). A version
-- with no footnotes has no rows.
select
    s.section_version_id,
    cast(f.idx as {{ dbt.type_int() }}) as footnote_number,
    {{ mogov.json_str('f.value', '$') }} as footnote_text
from {{ ref('stg_mo_revisor__sections') }} as s
cross join lateral {{ mogov.json_elements('s.footnotes', '$') }} as f
