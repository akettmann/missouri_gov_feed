-- One stable person_id per id a legislator has been given. The sources key the same person differently: Open States
-- sometimes holds two records for one person (a move between districts or chambers), and the House roster falls back
-- to mohouse:<member id> when its seat can't be tied to an Open States record. Every id seen in
-- int_officials__identity_terms gets one row: alias_id (as the source gave it) -> person_id (what the pipeline calls
-- the person). Rules, in order:
--   1. seed official_id_links, same_person: a curated id for a person the name rule can't join (statewide officers,
--      judges). basis = curated.
--   2. ids with the same exact full name (case, punctuation and spacing ignored: "Van Schoiack" and "VanSchoiack"
--      are one name, #228) are one person, basis = name_continuity, unless two of them hold different seats in more
--      than one shared year. The same seat in the
--      same year is how a split shows (Jean Evans, Joe Adams); different seats across several shared years mean two
--      people, while a single shared year is a hand-over between seats. A pair listed
--      as different_people in official_id_links also keeps that whole name apart.
--   2b. two names that differ only in the given name, one being the start of the other ("Steve"/"Steven" Roberts,
--      "Ken"/"Kenneth" Jamison; #263), are one person when each name belongs to exactly one such pair and the
--      two ids never hold different seats in the same year, and either share a seat in some year or follow each
--      other with no gap of more than a year (a move between chambers). A chain or a fork of such pairs is
--      ambiguous and joins nothing.
--   3. otherwise the id is its own person, basis = self.
-- Among merged ids the person_id is an Open States id over mohouse:, then the one whose service ends latest, then
-- the smaller id. The choice never looks at the latest roster year, so an official's id does not change when they
-- leave office.
-- Curated rows (official_id_links) take effect only once a maintainer has signed them off (checked_by filled).
-- Grain: one row per alias_id.
with terms as (
    select * from {{ ref('int_officials__identity_terms') }}
),

-- sq is the name with spaces removed: the key every name rule compares, so "van schoiack" equals "vanschoiack".
-- given is its first word and family the rest, for the given-name variant rule.
alias_names as (
    select
        alias_id,
        max(name_key) as name_key,
        max(year) as last_year,
        min(year) as first_year,
        case when alias_id like 'mohouse:%' then 0 else 1 end as is_openstates
    from terms
    group by alias_id
),

aliases as (
    select
        alias_id,
        name_key,
        last_year,
        first_year,
        is_openstates,
        replace(name_key, ' ', '') as sq,
        {{ mogov.regex_replace_all('name_key', ' .*$', '') }} as given
    from alias_names
),

-- the same name holding two different seats in more than one year. One shared year is a hand-over: a member sworn
-- into the Senate mid-year, or an Open States term dated a year early, still sits in the House roster that year.
seat_conflicts as (
    select distinct sq
    from (
        select
            a.sq,
            a.alias_id,
            b.alias_id as other_alias_id
        from terms as ta
        inner join aliases as a on ta.alias_id = a.alias_id
        inner join terms as tb on ta.year = tb.year and ta.alias_id < tb.alias_id
        inner join aliases as b on tb.alias_id = b.alias_id and a.sq = b.sq
        where ta.office <> tb.office or ta.district <> tb.district
        group by a.sq, a.alias_id, b.alias_id
        having count(distinct ta.year) > 1
    ) as pairs
),

separated as (
    select distinct a.sq
    from {{ ref('official_id_links') }} as l
    inner join aliases as a on l.alias_id = a.alias_id or l.person_id = a.alias_id
    where l.relation = 'different_people' and l.checked_by is not null
),

keep_apart as (
    select sq from seat_conflicts
    union
    select sq from separated
),

-- ids whose names differ only in the given name, one starting with the other, and whose seats fit as one person
variant_pairs as (
    select distinct
        a.sq as sq_a,
        b.sq as sq_b
    from aliases as a
    inner join aliases as b
        on
            a.sq < b.sq
            and substr(a.sq, length(a.given) + 1) = substr(b.sq, length(b.given) + 1)
            and length(substr(a.sq, length(a.given) + 1)) > 0
            and a.given <> b.given
            and length(a.given) >= 3
            and length(b.given) >= 3
            and (b.given like a.given || '%' or a.given like b.given || '%')
    where
        not exists (
            select 1
            from terms as ta
            inner join terms as tb on ta.year = tb.year
            where
                ta.alias_id = a.alias_id and tb.alias_id = b.alias_id
                and (ta.office <> tb.office or ta.district <> tb.district)
        )
        and (
            exists (
                select 1
                from terms as ta
                inner join terms as tb
                    on ta.year = tb.year and ta.office = tb.office and ta.district = tb.district
                where ta.alias_id = a.alias_id and tb.alias_id = b.alias_id
            )
            or (a.last_year < b.first_year and b.first_year - a.last_year <= 1)
            or (b.last_year < a.first_year and a.first_year - b.last_year <= 1)
        )
        and a.sq not in (select k.sq from keep_apart as k)
        and b.sq not in (select k.sq from keep_apart as k)
),

variant_counts as (
    select
        sq,
        count(*) as n_pairs
    from (
        select sq_a as sq from variant_pairs
        union all
        select sq_b as sq from variant_pairs
    ) as sides
    group by sq
),

-- each name that has exactly one variant partner, which also has exactly one
name_groups as (
    select
        p.sq_a as sq,
        p.sq_a as group_key
    from variant_pairs as p
    inner join variant_counts as ca on p.sq_a = ca.sq and ca.n_pairs = 1
    inner join variant_counts as cb on p.sq_b = cb.sq and cb.n_pairs = 1
    union all
    select
        p.sq_b as sq,
        p.sq_a as group_key
    from variant_pairs as p
    inner join variant_counts as ca on p.sq_a = ca.sq and ca.n_pairs = 1
    inner join variant_counts as cb on p.sq_b = cb.sq and cb.n_pairs = 1
),

keyed as (
    select
        a.alias_id,
        a.sq,
        a.last_year,
        a.is_openstates,
        coalesce(g.group_key, a.sq) as group_key
    from aliases as a
    left join name_groups as g on a.sq = g.sq
),

ranked as (
    select
        k.alias_id,
        k.group_key,
        row_number() over (
            partition by k.group_key
            order by
                k.is_openstates desc,
                k.last_year desc,
                k.alias_id asc
        ) as rn
    from keyed as k
    where not exists (
        select 1 from keep_apart as ka
        where ka.sq = k.sq
    )
),

name_person as (
    select
        k.alias_id,
        coalesce(r.alias_id, k.alias_id) as person_id
    from keyed as k
    left join ranked as r on k.group_key = r.group_key and r.rn = 1
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
