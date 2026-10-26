-- An Open States id whose only evidence is one undated term (no start, no House member id, one year: #512) must not
-- share a name with another id. Such an id has a single evidence year, so int_officials__person_ids rule 2 (a seat
-- conflict needs more than one shared year) can never keep it apart from a same-name id, and rule 2b (the chamber-move
-- check compares first and last year) sees a move where there is none. A collision would join or split wrongly, so it
-- is a sanity failure to resolve by hand (an official_id_links row, or a dated start), not something to guess (#519).
-- Compared as the person-id rules do: spaces removed. Today: 22 such ids (senators of 2018-2022), 0 collisions.
with terms as (
    select
        alias_id,
        year,
        term_start,
        house_member_id,
        name_key,
        {{ dbt.replace('name_key', "' '", "''") }} as sq
    from {{ ref('int_officials__identity_terms') }}
),

undated_only as (
    select
        alias_id,
        max(sq) as sq
    from terms
    where alias_id not like 'mohouse:%'
    group by alias_id
    having count(distinct year) = 1 and count(term_start) = 0 and count(house_member_id) = 0
),

names as (
    select
        alias_id,
        max(sq) as sq
    from terms
    group by alias_id
)

select
    u.alias_id as undated_alias_id,
    n.alias_id as same_name_alias_id,
    u.sq as name_key
from undated_only as u
inner join names as n on u.sq = n.sq and u.alias_id <> n.alias_id
