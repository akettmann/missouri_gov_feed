-- Sanity check: no section version has both a history note and a repeal note. int_mo_revisor__session_law_bills
-- stacks both kinds of note under the section version's id and reads each act's change from the acts before it in the
-- same note ("Repealed L. A and L. B"); with two notes on one version their acts would share act_index values and
-- the "and L." inheritance could follow the wrong note. Today: 0. If this fails, key the model's notes by note kind
-- too.
select
    s.section_version_id,
    s.history_note,
    r.note as repeal_note
from {{ ref('stg_mo_revisor__sections') }} as s
inner join {{ ref('stg_mo_revisor__repeals') }} as r
    on s.section_version_id = r.section_version_id
where
    s.history_note is not null
    and r.change_kind = 'repealed'
