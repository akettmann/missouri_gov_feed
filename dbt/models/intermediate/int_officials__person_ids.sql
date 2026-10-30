-- One stable person_id per id a legislator has been given. The sources key the same person differently: Open States
-- sometimes holds two records for one person (a move between districts or chambers), and the House roster falls back
-- to mohouse:<member id> when its seat can't be tied to an Open States record. Every id seen in
-- int_officials__identity_terms gets one row: alias_id (as the source gave it) -> person_id (what the pipeline calls
-- the person). Rules, in order:
--   1. seed official_id_links, same_person: a curated id for a person the name rule can't join (statewide officers,
--      judges). basis = curated. A row moves the whole person its alias_id was merged into by the rules below to the
--      person its person_id was merged into, so naming a merged id the rules did not choose, on either side, does
--      not split the person (#174, #682).
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
--   2d. duplicate stubs (#294, #292): Open States holds some members twice, once as a stub. An Open States id whose
--      only seat-term is a dated stub under 90 days joins another name when that name's dated term (90 days or more)
--      in the same office and district contains the stub and starts at most 7 days before it, the surnames match
--      (one side may drop a one-letter middle initial: "David A." / "David" Dolan) and the given names fit
--      (mogov.first_name_fit: "Martin" / "Marty" Jacobs; not "Daniel" / "Robert"), basis = duplicate_stub. Every id
--      of the stub's name must be such a stub, the stub must have exactly one such partner name, neither name may
--      be kept apart, and a stub name already in a rule 2b pair (Kenneth / Ken Jamison) is left to rule 2b. A
--      special-election successor never qualifies: its term starts on or after the predecessor's ends, or (when Open
--      States leaves a departed member's normal term end) months after the predecessor's term starts. The stub's
--      name joins the other name's group, so rule 2c still applies to the joined person.
--   2c. MO House member id continuity (#151): the House keeps one member id per person across sessions and name
--      changes (Mazzie Boyd, 2023, and Mazzie Christensen, 2024-26, are member 2381), so ids that share a House member
--      id are one person whatever their names, basis = member_id_continuity. This is applied after rules 2 and 2b
--      and joins the persons they made, so it also reaches ids the name rules keep apart. It skips an id that carries
--      more than one member id (Open States' Rick Roeber holds member 2215 and, through a seat-match error, Rebecca
--      Roeber's 1790, #152: the shared 1790 would join two people) and any id listed as different_people in
--      official_id_links. Only ids with a roster row (a House member id) take part; Senate-only ids rely on names.
--   3. otherwise the id is its own person, basis = self.
-- Among merged ids the person_id is an Open States id over mohouse:, then the one whose service ends latest, then
-- the one that is not a duplicate stub, then the smaller id. The choice never looks at the latest roster year, so
-- an official's id does not change when they leave office.
-- Curated rows (official_id_links) take effect only once a maintainer has signed them off (checked_by and checked_on
-- both filled, #174).
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

-- rest is the name after the given name with spaces removed ("adolan" for "david a dolan"), and core the same
-- without a leading one-letter middle initial ("dolan"), for the duplicate-stub rule 2d.
alias_parts as (
    select
        alias_id,
        name_key,
        last_year,
        first_year,
        is_openstates,
        {{ mogov.regex_replace_all('name_key', ' .*$', '') }} as given,
        {{ mogov.regex_replace_all('name_key', '^[^ ]* ?', '') }} as rest_key
    from alias_names
),

aliases as (
    select
        alias_id,
        name_key,
        last_year,
        first_year,
        is_openstates,
        replace(name_key, ' ', '') as sq,
        given,
        replace(rest_key, ' ', '') as rest,
        replace({{ mogov.regex_replace_all('rest_key', '^[a-z] ', '') }}, ' ', '') as core
    from alias_parts
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

-- a curated row counts once a maintainer has signed it off: checked_by and checked_on filled together (#174)
signed_links as (
    select
        alias_id,
        person_id,
        relation
    from {{ ref('official_id_links') }}
    where checked_by is not null and checked_on is not null
),

separated as (
    select distinct a.sq
    from signed_links as l
    inner join aliases as a on l.alias_id = a.alias_id or l.person_id = a.alias_id
    where l.relation = 'different_people'
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

-- rule 2d, duplicate stubs (#294, #292). An Open States id whose only seat-term is a dated stub under 90 days
-- (one office and district, start and end known).
stub_terms as (
    select
        alias_id,
        min(office) as office,
        min(district) as district,
        min(term_start) as term_start,
        max(term_end) as term_end
    from terms
    where alias_id not like 'mohouse:%'
    group by alias_id
    having
        count(distinct office) = 1
        and count(distinct district) = 1
        and count(term_start) = count(*)
        and count(term_end) = count(*)
        and {{
            dbt.datediff('min(term_start)', 'max(term_end)', 'day')
        }} < 90
),

-- another name's dated term in the same seat that contains the stub, starts at most 7 days before it and is no
-- stub itself; the surnames match (a dropped one-letter middle initial is allowed: "david a dolan" ~ "david dolan",
-- not "david b dolan") and the given names fit (mogov.first_name_fit: "martin" ~ "marty", not "daniel" ~ "robert").
-- A successor's term starts on or after the predecessor's ends, so it is never inside it; one inside a departed
-- member's on-paper term starts months after it, not within 7 days.
stub_candidates as (
    select distinct
        s.alias_id as stub_id,
        sa.sq as stub_sq,
        oa.sq as other_sq
    from stub_terms as s
    inner join aliases as sa on s.alias_id = sa.alias_id
    inner join terms as ot
        on
            s.office = ot.office and s.district = ot.district
            and s.term_start >= ot.term_start and s.term_end <= ot.term_end
            and s.term_start <= {{ dbt.dateadd('day', 7, 'ot.term_start') }}
    inner join aliases as oa on ot.alias_id = oa.alias_id
    where
        sa.sq <> oa.sq
        and {{
            dbt.datediff('ot.term_start', 'ot.term_end', 'day')
        }} >= 90
        and length(oa.core) > 0
        and (sa.rest = oa.rest or sa.core = oa.rest or sa.rest = oa.core)
        and {{ mogov.first_name_fit('sa.given', 'sa.given', 'oa.given') }} >= 1
),

-- a stub name joins the other name when it has exactly one candidate, every id of the stub name is such a stub,
-- neither name is kept apart, the stub name is not already in a rule 2b pair (Kenneth / Ken Jamison) and the other
-- name is no stub name itself. It joins the other name's group (its rule 2b group, if it has one).
stub_links as (
    select
        stub_sq,
        min(other_sq) as other_sq
    from stub_candidates
    group by stub_sq
    having count(distinct other_sq) = 1
),

stub_groups as (
    select
        l.stub_sq as sq,
        coalesce(g.group_key, l.other_sq) as group_key
    from stub_links as l
    left join name_groups as g on l.other_sq = g.sq
    where
        not exists (
            select 1 from aliases as a
            where
                a.sq = l.stub_sq
                and a.alias_id not in (select sc.stub_id from stub_candidates as sc)
        )
        and l.stub_sq not in (select k.sq from keep_apart as k)
        and l.other_sq not in (select k.sq from keep_apart as k)
        and l.stub_sq not in (select ng.sq from name_groups as ng)
        and l.other_sq not in (select sc.stub_sq from stub_candidates as sc)
),

keyed as (
    select
        a.alias_id,
        a.sq,
        a.last_year,
        a.is_openstates,
        sg.sq is not null as via_stub,
        coalesce(g.group_key, sg.group_key, a.sq) as group_key
    from aliases as a
    left join name_groups as g on a.sq = g.sq
    left join stub_groups as sg on a.sq = sg.sq
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
                case when k.via_stub then 1 else 0 end asc,
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
        k.via_stub,
        coalesce(r.alias_id, k.alias_id) as person_id
    from keyed as k
    left join ranked as r on k.group_key = r.group_key and r.rn = 1
),

-- rule 2c is a single pass, not full connected components: ids join through a member id's anchor once, so a chain
-- across 3+ persons (A shares a member id with B, B another with C) can stay split. It never wrongly joins; the
-- data test assert_house_member_id_one_person flags the leftovers through its shared_id branch.
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
            from signed_links as l
            where
                l.relation = 'different_people'
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
        n.via_stub,
        mp.person_id is not null as via_member_id
    from name_person as n
    left join member_person as mp on n.alias_id = mp.alias_id
),

-- a signed same_person row moves the whole person its alias_id was merged into, so naming an id the rules merged
-- but did not choose still moves every id of that person (#174). Its target is read the same way: a person_id the
-- rules merged into another id is replaced by that person's chosen id, so the moved person joins the target's
-- whole person instead of splitting it (#682). A target no rule saw (a mojudge: id) is kept as written. Two signed
-- rows sending one person to different ids are a seed error; the smaller id is taken so the output stays
-- deterministic.
same_person as (
    select
        n.person_id as merged_person_id,
        min(coalesce(t.person_id, l.person_id)) as person_id
    from signed_links as l
    inner join merged as n on l.alias_id = n.alias_id
    left join merged as t on l.person_id = t.alias_id
    where l.relation = 'same_person'
    group by n.person_id
)

select
    n.alias_id,
    coalesce(c.person_id, n.person_id) as person_id,
    case
        when c.person_id is not null then 'curated'
        when n.via_member_id and n.person_id <> n.name_person_id then 'member_id_continuity'
        when n.via_stub and n.person_id <> n.alias_id then 'duplicate_stub'
        when n.person_id <> n.alias_id then 'name_continuity'
        else 'self'
    end as basis
from merged as n
left join same_person as c on n.person_id = c.merged_person_id
