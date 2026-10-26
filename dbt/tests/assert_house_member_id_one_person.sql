-- A MO House member id is one person (#151): the House keeps one id per person across sessions and name changes
-- (Mazzie Boyd and Mazzie Christensen are member 2381). Two checks over the House roster's person keys:
--   shared_id    two person_keys carry one member id, so int_officials__person_ids missed a name change. The id
--                holder is left out when its raw key also carries a second member id (Open States' Rick Roeber
--                holds Rebecca Roeber's 1790 through a seat-match error, #152): the person-id rule skips it.
--   two_ids_at_once  one person_key holds two member ids in one session: the rule joined two people who
--                served at the same time (a member id reused for someone else, or a bad merge).
with roster as (
    select distinct
        session_code,
        house_member_id,
        raw_person_key,
        person_key
    from {{ ref('int_mo_house__member_identity') }}
),

multi_id_keys as (
    select raw_person_key
    from roster
    group by raw_person_key
    having count(distinct house_member_id) > 1
),

shared_id as (
    select
        'shared_id' as problem,
        r.house_member_id as detail,
        count(distinct r.person_key) as n
    from roster as r
    where r.raw_person_key not in (select m.raw_person_key from multi_id_keys as m)
    group by r.house_member_id
    having count(distinct r.person_key) > 1
),

two_ids_at_once as (
    select
        'two_ids_at_once' as problem,
        person_key as detail,
        count(distinct house_member_id) as n
    from roster
    group by person_key, session_code
    having count(distinct house_member_id) > 1
)

select * from shared_id
union all
select * from two_ids_at_once
