-- Sponsors, co-sponsors, handlers and conferees of each House bill, matched to officials where possible.
-- The House numbers senators 200 + senate district. A representative is matched on (session, district)
-- through the House roster; a senator on the senate seat held that year. Either way the listed name must
-- contain the member's surname. Unmatched rows (former members, typos) keep official_id null.
with sponsors as (
    select
        *,
        {{ mogov.name_key('sponsor_name') }} as sponsor_key,
        case when sponsor_district > 200 then 'state_senate' else 'state_house' end as sponsor_chamber
    from {{ ref('stg_mo_house__bill_sponsors') }}
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
