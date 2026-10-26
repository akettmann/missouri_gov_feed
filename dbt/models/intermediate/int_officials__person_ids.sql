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
--      names never hold different seats in the same year (across all ids of both names), and either hold a seat
--      at the same time (their dated terms in one seat overlap: start_a < end_b and start_b < end_a, an open term
--      ending 9999-12-31; the same start day overlaps, one term ending the day the other starts does not), or
--      follow each other within a year in a different chamber (a move, as Roberts went House to Senate). Overlap
--      alone is not enough: Open States often leaves a member who left mid-term with the normal term end, so a
--      special-election successor overlaps on paper (Silvey to 2018-12-31, Lauren Arthur from 2018-09-12, SD17). The
--      shared-seat case also needs one term to be a stub (under 90 days) inside the other, starting within 31 days
--      of it; equal or nested multi-year terms do not qualify (Open States' placeholder 2013-01-01 starts, #332).
--      Years alone cannot decide the shared-seat case: Kenneth Jamison (2025 only) inside Ken Jamison (2025-26) is a
--      duplicate, but Danielle Smith (2019 only, or 2026 only after a special election) inside a Dan Smith
--      successor's span looks the same by year. Dates tell them apart: Kenneth's term is a 26-day stub that overlaps
--      Ken's, while a successor's term starts on or after the predecessor's ends (or is no stub). Undated
--      House-roster rows prove no overlap. A name left with more than one partner (a chain or a fork) is ambiguous
--      and joins nothing.
--   2c. MO House member id continuity (#151): the House keeps one member id per person across sessions and name
--      changes (Mazzie Boyd, 2023, and Mazzie Christensen, 2024-26, are member 2381), so ids that share a House member
--      id are one person whatever their names, basis = member_id_continuity. This is applied after rules 2 and 2b
--      and joins the persons they made, so it also reaches ids the name rules keep apart. It skips an id that carries
--      more than one member id (Open States' Rick Roeber holds member 2215 and, through a seat-match error, Rebecca
--      Roeber's 1790, #152: the shared 1790 would join two people) and any id listed as different_people in
--      official_id_links. Only ids with a roster row (a House member id) take part; Senate-only ids rely on names.
--   3. otherwise the id is its own person, basis = self.
-- Among merged ids the person_id is an Open States id over mohouse:, then the one whose service ends latest, then
-- the smaller id. The choice never looks at the latest roster year, so an official's id does not change when they
-- leave office.
-- Curated rows (official_id_links) take effect only once a maintainer has signed them off (checked_by filled).
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

-- names (not ids) that differ only in the given name, one starting with the other, and whose seats fit as one
-- person. A shared seat joins them only when their dated terms in it overlap in time. Every id of either name
-- is checked, so another id of one name holding a different seat in the other name's years rules the pair out.
name_spans as (
    select
        sq,
        min(given) as given,
        min(first_year) as first_year,
        max(last_year) as last_year
    from aliases
    group by sq
),

name_terms as (
    select
        a.sq,
        t.year,
        t.office,
        t.district,
        t.term_start,
        t.term_end,
        {{
            dbt.datediff('t.term_start', 't.term_end', 'day')
        }} as term_days,
        {{ dbt.dateadd('day', 31, 't.term_start') }} as start_plus_31
    from terms as t
    inner join aliases as a on t.alias_id = a.alias_id
),

variant_pairs as (
    select distinct
        a.sq as sq_a,
        b.sq as sq_b
    from name_spans as a
    inner join name_spans as b
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
            from name_terms as ta
            inner join name_terms as tb on ta.year = tb.year
            where
                ta.sq = a.sq and tb.sq = b.sq
                and (ta.office <> tb.office or ta.district <> tb.district)
        )
        and (
            (
                -- the names hold one seat at the same time. Succession (a term starting on/after the other
                -- ends: Dan 2019, Danielle 2019-21) is not overlap; Kenneth's stub inside Ken's term is.
                exists (
                    select 1
                    from name_terms as ta
                    inner join name_terms as tb
                        on ta.office = tb.office and ta.district = tb.district
                    where
                        ta.sq = a.sq and tb.sq = b.sq
                        and ta.term_start < tb.term_end and tb.term_start < ta.term_end
                        -- and one is a short stub (under 90 days) inside the other, starting within 31 days of it.
                        -- Open States often leaves a mid-term departure's end at the normal term end, so a
                        -- successor's term overlaps on paper without being inside the predecessor's; and it gives
                        -- some pre-2015 terms a placeholder 2013-01-01 start, so two different people can hold
                        -- equal or nested multi-year terms (Smith/Sisco, Fowler/Hubrecht; #332)
                        and (
                            (
                                ta.term_start >= tb.term_start and ta.term_end <= tb.term_end
                                and ta.term_days < 90 and ta.term_start <= tb.start_plus_31
                            )
                            or (
                                tb.term_start >= ta.term_start and tb.term_end <= ta.term_end
                                and tb.term_days < 90 and tb.term_start <= ta.start_plus_31
                            )
                        )
                )
            )
            -- no shared seat-year: only a move between chambers, one name ending as the other begins. The same
            -- chamber a year apart is a successor ("Dan" Smith, then "Danielle" Smith in the same seat).
            or (
                a.last_year < b.first_year and b.first_year - a.last_year <= 1
                and exists (
                    select 1
                    from name_terms as ta
                    inner join name_terms as tb on ta.year = a.last_year and tb.year = b.first_year
                    where ta.sq = a.sq and tb.sq = b.sq and ta.office <> tb.office
                )
                and not exists (
                    select 1
                    from name_terms as ta
                    inner join name_terms as tb on ta.year = a.last_year and tb.year = b.first_year
                    where ta.sq = a.sq and tb.sq = b.sq and ta.office = tb.office
                )
            )
            or (
                b.last_year < a.first_year and a.first_year - b.last_year <= 1
                and exists (
                    select 1
                    from name_terms as ta
                    inner join name_terms as tb on tb.year = b.last_year and ta.year = a.first_year
                    where ta.sq = a.sq and tb.sq = b.sq and ta.office <> tb.office
                )
                and not exists (
                    select 1
                    from name_terms as ta
                    inner join name_terms as tb on tb.year = b.last_year and ta.year = a.first_year
                    where ta.sq = a.sq and tb.sq = b.sq and ta.office = tb.office
                )
            )
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

-- rule 2c. An id takes part when its roster rows carry exactly one House member id and it is not a signed
-- different_people id. Ids that share a member id are one person: each such id's name-rule person is pulled to
-- the smallest person any of them has, so the persons the name rules made are joined, not just the single ids.
member_aliases as (
    select
        t.alias_id,
        min(t.house_member_id) as house_member_id
    from terms as t
    where
        t.house_member_id is not null
        and not exists (
            select 1
            from {{ ref('official_id_links') }} as l
            where
                l.relation = 'different_people' and l.checked_by is not null
                and (l.alias_id = t.alias_id or l.person_id = t.alias_id)
        )
    group by t.alias_id
    having count(distinct t.house_member_id) = 1
),

member_persons as (
    select
        m.house_member_id,
        m.alias_id,
        n.person_id as name_person_id
    from member_aliases as m
    inner join name_person as n on m.alias_id = n.alias_id
),

member_anchors as (
    select
        house_member_id,
        min(name_person_id) as anchor_id
    from member_persons
    group by house_member_id
    having count(distinct name_person_id) > 1
),

-- the person each name-rule person is joined into: the smallest anchor of a member id any of its ids carries
person_anchors as (
    select
        p.name_person_id,
        min(a.anchor_id) as anchor_id
    from member_persons as p
    inner join member_anchors as a on p.house_member_id = a.house_member_id
    group by p.name_person_id
),

-- every id of a joined person (its name-rule person's other ids included) is a candidate for the joined person_id;
-- an anchor person is in person_anchors too, as its own anchor
member_groups as (
    select
        n.alias_id,
        pa.anchor_id as group_key
    from name_person as n
    inner join person_anchors as pa on n.person_id = pa.name_person_id
),

member_ranked as (
    select
        g.alias_id,
        g.group_key,
        row_number() over (
            partition by g.group_key
            order by
                a.is_openstates desc,
                a.last_year desc,
                g.alias_id asc
        ) as rn
    from member_groups as g
    inner join aliases as a on g.alias_id = a.alias_id
),

member_person as (
    select
        g.alias_id,
        r.alias_id as person_id
    from member_groups as g
    inner join member_ranked as r on g.group_key = r.group_key and r.rn = 1
),

merged as (
    select
        n.alias_id,
        coalesce(mp.person_id, n.person_id) as person_id,
        n.person_id as name_person_id,
        mp.person_id is not null as via_member_id
    from name_person as n
    left join member_person as mp on n.alias_id = mp.alias_id
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
        when n.via_member_id and n.person_id <> n.name_person_id then 'member_id_continuity'
        when n.person_id <> n.alias_id then 'name_continuity'
        else 'self'
    end as basis
from merged as n
left join same_person as by_alias on n.alias_id = by_alias.alias_id
left join same_person as by_person on n.person_id = by_person.alias_id
