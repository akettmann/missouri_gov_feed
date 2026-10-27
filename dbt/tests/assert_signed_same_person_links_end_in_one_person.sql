-- Every signed same_person row in official_id_links ends with its two ids in one person: the person_id the model
-- gives the row's alias_id equals the one it gives the row's person_id (or the person_id as written, for a target the
-- model never saw, such as a mojudge: id). int_officials__person_ids resolves a signed row in one step, so a chain
-- (A -> B, then B' -> C with B' in B's person) leaves A's person on B's chosen id while B's person moves to C: one
-- person, two ids (#691). Two signed rows sending one person to different persons also fail here, since only the
-- smaller resolved id wins. Fix the seed: point every row of the chain at its final person.
with signed_same_person as (
    select
        alias_id,
        person_id
    from {{ ref('official_id_links') }}
    where
        relation = 'same_person'
        and checked_by is not null
        and checked_on is not null
)

select
    l.alias_id,
    l.person_id,
    a.person_id as alias_person_id,
    coalesce(t.person_id, l.person_id) as target_person_id
from signed_same_person as l
inner join {{ ref('int_officials__person_ids') }} as a on l.alias_id = a.alias_id
left join {{ ref('int_officials__person_ids') }} as t on l.person_id = t.alias_id
where a.person_id <> coalesce(t.person_id, l.person_id)
