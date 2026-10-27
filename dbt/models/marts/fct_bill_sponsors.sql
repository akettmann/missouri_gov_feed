-- Sponsors, co-sponsors, handlers and conferees of each House bill, matched to officials where possible.
-- The House numbers senators 200 + senate district. A representative is matched on (session, district)
-- through the House roster; a senator on the senate seat held that year. Either way the listed name must
-- contain the member's surname. The House XML lists a representative's latest district for every session, so
-- a member whose district number changed (the 2022 redistricting) never matches on the session's own district;
-- those rows match on (session, surname) among members on that session's roster who held the listed district in
-- some session and whose given name the sponsor's name carries (the roster is an end-of-session snapshot, so a
-- surname alone could name a different same-surname member). Two candidate people leave the row unmatched.
-- Unmatched rows (former members, typos) keep official_id null.
-- The XML lists the latest district too for a representative who later moved to the Senate, as 200 + the senate
-- district, so his House-era rows look like a senator's (#646). A sponsor, co-sponsor, handler or House conferee of
-- a House bill is a House member in that session, whatever district is listed: such a senate-listed row matches the
-- House roster on (session, surname, given name) when that person held the listed senate seat in some session
-- (the order is not checked: the XML lists the latest district), and then
-- counts as state_house with the roster's district. It never matches two people. A row that finds no one on the
-- House roster keeps the listed-district reading (a defensive fallback: in current data every senate-listed
-- House-role row finds its person on the House roster, so it does not trigger).
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
        case when sp.sponsor_district > 200 then 'state_senate' else 'state_house' end as sponsor_chamber,
        -- a House member in the session, whatever the listed district says: senators only sit as Senate conferees
        -- (or sponsor a Senate bill), never as these
        (
            sp.sponsor_type in ('Handler', 'HouseConferee')
            or (sp.sponsor_type in ('Sponsor', 'Co-Sponsor') and left(sp.bill, 1) = 'H')
        ) as is_house_role
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
        and (
            ' ' || s.sponsor_key || ' ' like '% ' || {{ mogov.name_key('m.first_name') }} || ' %'
            or s.sponsor_key = {{ mogov.name_key('m.full_name') }}
        )
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

switch_match as (
    select
        s.session_code,
        s.bill,
        s.sponsor_type,
        s.sponsor_name,
        max(m.person_key) as person_key,
        max(m.district_number) as house_district
    from sponsors as s
    inner join {{ ref('int_mo_house__member_identity') }} as m
        on
            s.session_code = m.session_code
            and ' ' || s.sponsor_key || ' ' like '% ' || m.surname_key || ' %'
            and (
                ' ' || s.sponsor_key || ' ' like '% ' || {{ mogov.name_key('m.first_name') }} || ' %'
                or s.sponsor_key = {{ mogov.name_key('m.full_name') }}
            )
    inner join {{ ref('int_mo_legislators__seats') }} as seat
        on
            seat.chamber = 'upper'
            and m.person_key = seat.person_id
            and s.sponsor_district - 200 = seat.district_number
    where s.sponsor_chamber = 'state_senate' and s.is_house_role
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
    left join switch_match as sw
        on
            s.session_code = sw.session_code
            and s.bill = sw.bill
            and s.sponsor_type = sw.sponsor_type
            and s.sponsor_name = sw.sponsor_name
    where s.sponsor_chamber = 'state_senate' and sw.bill is null
    group by s.session_code, s.bill, s.sponsor_type, s.sponsor_name
    having count(distinct seat.person_id) = 1
),

matches as (
    select
        *,
        cast(null as integer) as house_district,
        false as is_switch
    from house_match
    union all
    select
        *,
        cast(null as integer) as house_district,
        false as is_switch
    from redistricted_match
    union all
    select
        *,
        cast(null as integer) as house_district,
        false as is_switch
    from senate_match
    union all
    select
        *,
        true as is_switch
    from switch_match
)

select distinct
    s.session_code,
    s.bill,
    s.sponsor_type,
    s.sponsor_name,
    case when m.is_switch then 'state_house' else s.sponsor_chamber end as sponsor_chamber,
    case
        when m.is_switch then m.house_district
        when s.sponsor_chamber = 'state_senate' then s.sponsor_district - 200
        else s.sponsor_district
    end as sponsor_district,
    o.official_id
from sponsors as s
left join matches as m
    on
        s.session_code = m.session_code
        and s.bill = m.bill
        and s.sponsor_type = m.sponsor_type
        and s.sponsor_name = m.sponsor_name
left join {{ ref('dim_official') }} as o on m.person_key = o.official_id
