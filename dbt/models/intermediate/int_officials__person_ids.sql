-- One stable person_id per id a legislator has been given. The sources key the same person differently: Open States
-- sometimes holds two records for one person (a move between districts or chambers), and the House roster falls back
-- to mohouse:<member id> when its seat can't be tied to an Open States record. Every id seen in
-- int_officials__identity_terms gets one row: alias_id (as the source gave it) -> person_id (what the pipeline calls
-- the person). Rules, in order:
--   1. seed official_id_links, same_person: a curated id for a person the name rule can't join (statewide officers,
--      judges). basis = curated.
--   2. ids with the same exact full name (case, punctuation and spacing ignored) are one person, basis =
--      name_continuity, unless two of them hold different seats in more than one shared year. The same seat in the
--      same year is how a split shows (Jean Evans, Joe Adams); different seats across several shared years mean two
--      people, while a single shared year is a hand-over between seats. A pair listed
--      as different_people in official_id_links also keeps that whole name apart.
--   3. otherwise the id is its own person, basis = self.
-- Among merged ids the person_id is an Open States id over mohouse:, then the one whose service ends latest, then
-- the smaller id. The choice never looks at the latest roster year, so an official's id does not change when they
-- leave office.
-- Curated rows (official_id_links) take effect only once a maintainer has signed them off (checked_by filled).
-- Grain: one row per alias_id.
with terms as (
    select * from {{ ref('int_officials__identity_terms') }}
),

aliases as (
    select
        alias_id,
        max(name_key) as name_key,
        max(year) as last_year,
        case when alias_id like 'mohouse:%' then 0 else 1 end as is_openstates
    from terms
    group by alias_id
),

-- the same name holding two different seats in more than one year. One shared year is a hand-over: a member sworn
-- into the Senate mid-year, or an Open States term dated a year early, still sits in the House roster that year.
seat_conflicts as (
    select distinct name_key
    from (
        select
            a.name_key,
            a.alias_id,
            b.alias_id as other_alias_id
        from terms as a
        inner join terms as b
            on
                a.name_key = b.name_key
                and a.year = b.year
                and a.alias_id < b.alias_id
                and (a.office <> b.office or a.district <> b.district)
        group by a.name_key, a.alias_id, b.alias_id
        having count(distinct a.year) > 1
    ) as pairs
),

separated as (
    select distinct a.name_key
    from {{ ref('official_id_links') }} as l
    inner join aliases as a on l.alias_id = a.alias_id or l.person_id = a.alias_id
    where l.relation = 'different_people' and l.checked_by is not null
),

keep_apart as (
    select name_key from seat_conflicts
    union
    select name_key from separated
),

ranked as (
    select
        a.alias_id,
        a.name_key,
        row_number() over (
            partition by a.name_key
            order by
                a.is_openstates desc,
                a.last_year desc,
                a.alias_id asc
        ) as rn
    from aliases as a
    where not exists (
        select 1 from keep_apart as k
        where k.name_key = a.name_key
    )
),

name_person as (
    select
        a.alias_id,
        coalesce(r.alias_id, a.alias_id) as person_id
    from aliases as a
    left join ranked as r on a.name_key = r.name_key and r.rn = 1
),

same_person as (
    select
        alias_id,
        person_id
    from {{ ref('official_id_links') }}
    where relation = 'same_person' and checked_by is not null
)

select
    n.alias_id,
    coalesce(by_alias.person_id, by_person.person_id, n.person_id) as person_id,
    case
        when by_alias.person_id is not null or by_person.person_id is not null then 'curated'
        when n.person_id <> n.alias_id then 'name_continuity'
        else 'self'
    end as basis
from name_person as n
left join same_person as by_alias on n.alias_id = by_alias.alias_id
left join same_person as by_person on n.person_id = by_person.alias_id
