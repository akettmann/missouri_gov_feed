-- Sponsors, co-sponsors, handlers and conferees of each House bill, matched to officials where possible.
-- The House numbers senators 200 + senate district. A representative is matched on (session, district)
-- through the House roster; a senator on the senate seat held that year. Either way the listed name must
-- contain the member's surname. The House XML lists a representative's latest district for every session, so
-- a member whose district number changed (the 2022 redistricting) never matches on the session's own district;
-- those rows match on (session, surname) among members on that session's roster who held the listed district in
-- some session. Two candidate people leave the row unmatched. Unmatched rows (former members, typos) keep
-- official_id null.
-- Re-listed bills (status 'relisted for governor message', int_bills__status) are left out: the House lists the
-- previous session's appropriation bill again only for the governor's message, repeating its sponsors, so keeping
-- them would count the budget chair's sponsorship twice. The original's row carries the sponsorship.
with relisted as (
    select
        session_code,
        bill
    from {{ ref('int_bills__status') }}
    where status = 'relisted for governor message'
),

sponsors as (
    select
        sp.*,
        {{ mogov.name_key('sp.sponsor_name') }} as sponsor_key,
        case when sp.sponsor_district > 200 then 'state_senate' else 'state_house' end as sponsor_chamber
    from {{ ref('stg_mo_house__bill_sponsors') }} as sp
    left join relisted as rl on sp.session_code = rl.session_code and sp.bill = rl.bill
    where rl.bill is null
),

house_match as (
    select
        s.session_code,
        s.bill,
        s.sponsor_type,
        s.sponsor_name,
        max(m.person_key) as person_key
    from sponsors as s
    inner join {{ ref('int_mo_house__member_identity') }} as m
        on
            s.session_code = m.session_code
            and s.sponsor_district = m.district_number
            and ' ' || s.sponsor_key || ' ' like '% ' || m.surname_key || ' %'
    where s.sponsor_chamber = 'state_house'
    group by s.session_code, s.bill, s.sponsor_type, s.sponsor_name
    having count(distinct m.person_key) = 1
),

redistricted_match as (
    select
        s.session_code,
        s.bill,
        s.sponsor_type,
        s.sponsor_name,
        max(m.person_key) as person_key
    from sponsors as s
    inner join {{ ref('int_mo_house__member_identity') }} as m
        on
            s.session_code = m.session_code
            and ' ' || s.sponsor_key || ' ' like '% ' || m.surname_key || ' %'
    inner join {{ ref('int_mo_house__member_identity') }} as held
        on
            m.person_key = held.person_key
            and s.sponsor_district = held.district_number
    where
        s.sponsor_chamber = 'state_house'
        and not exists (
            select 1
            from {{ ref('int_mo_house__member_identity') }} as own
            where
                own.session_code = s.session_code
                and own.district_number = s.sponsor_district
                and ' ' || s.sponsor_key || ' ' like '% ' || own.surname_key || ' %'
        )
    group by s.session_code, s.bill, s.sponsor_type, s.sponsor_name
    having count(distinct m.person_key) = 1
),

senate_match as (
    select
        s.session_code,
        s.bill,
        s.sponsor_type,
        s.sponsor_name,
        max(seat.person_id) as person_key
    from sponsors as s
    inner join {{ ref('int_mo_legislators__seats') }} as seat
        on
            seat.chamber = 'upper'
            and s.sponsor_district - 200 = seat.district_number
            and s.session_year between extract(year from seat.start_date) and extract(year from seat.end_date)
            and ' ' || s.sponsor_key || ' ' like '% ' || seat.surname_key || ' %'
    where s.sponsor_chamber = 'state_senate'
    group by s.session_code, s.bill, s.sponsor_type, s.sponsor_name
    having count(distinct seat.person_id) = 1
),

matches as (
    select * from house_match
    union all
    select * from redistricted_match
    union all
    select * from senate_match
)

select distinct
    s.session_code,
    s.bill,
    s.sponsor_type,
    s.sponsor_name,
    s.sponsor_chamber,
    case when s.sponsor_chamber = 'state_senate' then s.sponsor_district - 200 else s.sponsor_district end
        as sponsor_district,
    o.official_id
from sponsors as s
left join matches as m
    on
        s.session_code = m.session_code
        and s.bill = m.bill
        and s.sponsor_type = m.sponsor_type
        and s.sponsor_name = m.sponsor_name
left join {{ ref('dim_official') }} as o on m.person_key = o.official_id
