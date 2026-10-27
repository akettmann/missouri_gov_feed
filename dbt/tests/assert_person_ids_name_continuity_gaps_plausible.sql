-- Sanity check (#660, #174 item 2): the name rules in int_officials__person_ids (rules 2 and 2b, basis
-- name_continuity) join ids by name alone, with no check on district or gap length, so two different people with
-- the same name serving years apart would merge silently (assert_official_ids_one_per_person only looks at
-- overlaps). Each id of a person that the name rules built must sit plausibly next to another id of that person:
--   - their years touch (a shared year, or one id's last year is the year before the other's first): any seat
--     change is then a move (House to Senate, a redistricted seat), or
--   - they hold the same seat (office and district) and the gap is at most 8 years: a member returning to the seat.
-- An id with neither is listed with its nearest other id. Two pieces of evidence outrank the name and exempt a pair:
-- the same House member id on both (the House keeps one member id per person: Deb Lavender HD90 2017-20 and HD98
-- 2023-24 are member 1786, Mark Matthiesen HD70 and HD107 member 1937), and a same_person row in official_id_links
-- signed off by a maintainer (checked_by and checked_on filled).
-- Measured on a full build (2026-10-27): 26 name_continuity ids, in 26 persons of 2 ids each (27 before Webber was
-- signed). 23 persons touch in time; Joe Adams returns to HD86 after 2 years; Lavender and Matthiesen are exempt
-- by member id. Stephen Webber (HD46 to 2016, SD19 from 2025: 9 years, another chamber) would fail on the name
-- alone. A maintainer signed off that he is one person (#504, PR #511, #663), so his row in official_id_links is
-- signed: his ids are now basis curated, and the signed pair is exempt. It lists nothing, so it is an error (#663).
-- A signed same_person row makes every id of the person it moves basis curated, including ids the name rules joined
-- to the signed id, so curated persons are checked too (#682): the sign-off exempts only the pair it names, and an
-- id the name rules wrongly joined to that person is still listed.
{{ config(severity='error') }}

with person_ids as (
    select * from {{ ref('int_officials__person_ids') }}
),

-- persons the name rules built (the chosen id itself is basis self, so take every id of such a person), and persons
-- a signed row moved, whose ids are all basis curated whatever joined them
name_persons as (
    select distinct person_id
    from person_ids
    where basis in ('name_continuity', 'curated')
),

spans as (
    select
        p.person_id,
        p.alias_id,
        min(t.year) as first_year,
        max(t.year) as last_year
    from person_ids as p
    inner join name_persons as n on p.person_id = n.person_id
    inner join {{ ref('int_officials__identity_terms') }} as t on p.alias_id = t.alias_id
    group by p.person_id, p.alias_id
),

seats as (
    select distinct
        alias_id,
        office,
        coalesce(district, '') as district
    from {{ ref('int_officials__identity_terms') }}
),

member_ids as (
    select distinct
        alias_id,
        house_member_id
    from {{ ref('int_officials__identity_terms') }}
    where house_member_id is not null
),

signed as (
    select
        alias_id,
        person_id
    from {{ ref('official_id_links') }}
    where relation = 'same_person' and checked_by is not null and checked_on is not null
),

pairs as (
    select
        a.person_id,
        a.alias_id,
        a.first_year,
        a.last_year,
        b.alias_id as other_alias_id,
        b.first_year as other_first_year,
        b.last_year as other_last_year,
        -- years between the two spans: 0 when they share a year, 1 when one ends the year before the other starts
        case
            when a.last_year < b.first_year then b.first_year - a.last_year
            when b.last_year < a.first_year then a.first_year - b.last_year
            else 0
        end as gap_years,
        exists(
            select 1
            from seats as sa
            inner join seats as sb on sa.office = sb.office and sa.district = sb.district
            where sa.alias_id = a.alias_id and sb.alias_id = b.alias_id
        ) as same_seat,
        exists(
            select 1
            from member_ids as ma
            inner join member_ids as mb on ma.house_member_id = mb.house_member_id
            where ma.alias_id = a.alias_id and mb.alias_id = b.alias_id
        ) as same_member_id,
        exists(
            select 1
            from signed as s
            where
                (s.alias_id = a.alias_id and s.person_id = b.alias_id)
                or (s.alias_id = b.alias_id and s.person_id = a.alias_id)
        ) as signed_off
    from spans as a
    inner join spans as b on a.person_id = b.person_id and a.alias_id <> b.alias_id
),

judged as (
    select
        *,
        case
            when gap_years <= 1 or (same_seat and gap_years <= 8) or same_member_id or signed_off then 1
            else 0
        end as plausible,
        row_number() over (partition by alias_id order by gap_years asc, other_alias_id asc) as nearest
    from pairs
)

select
    j.person_id,
    j.alias_id,
    j.first_year,
    j.last_year,
    j.other_alias_id,
    j.other_first_year,
    j.other_last_year,
    j.gap_years,
    j.same_seat
from judged as j
where
    j.nearest = 1
    and not exists (
        select 1
        from judged as ok
        where ok.alias_id = j.alias_id and ok.plausible = 1
    )
