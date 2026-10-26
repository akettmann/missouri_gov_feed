-- An Open States id whose only evidence is one undated term (no start, no House member id, one year: #512) must not
-- share a name with another id, nor carry a rule 2b variant of another id's name. Such an id has a single evidence
-- year, so int_officials__person_ids rule 2 (a seat conflict needs more than one shared year) can never keep it apart
-- from a same-name id, and rule 2b (the chamber-move check compares first and last year) sees a chamber move where
-- there may be concurrent service, joining two people or two names wrongly. A collision is a sanity failure to
-- resolve by hand (an official_id_links row, or a dated start), not something to guess (#519).
-- rule '2': same name once spaces are removed. rule '2b': the same family part after the given name, different given
-- names of 3+ characters, one a prefix of the other (Dan / Daniel Brown); this is the variant_pairs join of
-- int_officials__person_ids, kept in step with it. Today: 22 such ids (senators of 2018-2022), 0 collisions.
with terms as (
    select distinct
        alias_id,
        year,
        term_start,
        house_member_id,
        {{ dbt.replace('name_key', "' '", "''") }} as sq,
        {{ mogov.regex_replace_all('name_key', ' .*$', '') }} as given
    from {{ ref('int_officials__identity_terms') }}
),

undated_ids as (
    select alias_id
    from terms
    group by alias_id
    having count(distinct year) = 1 and count(term_start) = 0 and count(house_member_id) = 0
),

undated_only as (
    select distinct
        t.alias_id,
        t.sq,
        t.given
    from terms as t
    inner join undated_ids as i on t.alias_id = i.alias_id
    where t.alias_id not like 'mohouse:%'
),

names as (
    select distinct
        alias_id,
        sq,
        given
    from terms
),

pairs as (
    select
        u.alias_id as undated_alias_id,
        n.alias_id as same_name_alias_id,
        u.sq as name_key,
        case when u.sq = n.sq then '2' else '2b' end as rule
    from undated_only as u
    inner join names as n
        on
            u.alias_id <> n.alias_id
            and (
                u.sq = n.sq
                or (
                    substr(u.sq, length(u.given) + 1) = substr(n.sq, length(n.given) + 1)
                    and length(substr(u.sq, length(u.given) + 1)) > 0
                    and u.given <> n.given
                    and length(u.given) >= 3
                    and length(n.given) >= 3
                    and (n.given like u.given || '%' or u.given like n.given || '%')
                )
            )
)

select * from pairs
