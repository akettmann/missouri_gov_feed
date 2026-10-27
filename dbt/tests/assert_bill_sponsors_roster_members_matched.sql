-- Sanity check: a House sponsor name that matched an official in one session must also match in every session
-- where that same person is on the House roster under the same surname. The House XML lists a member's latest
-- district for every session, so a member who changed district (the 2022 redistricting) lost every earlier
-- session's rows (#636). Counts the unmatched rows that should have matched.
select
    u.session_code,
    u.bill,
    u.sponsor_type,
    u.sponsor_name
from {{ ref('fct_bill_sponsors') }} as u
inner join (
    select distinct
        sponsor_name,
        official_id
    from {{ ref('fct_bill_sponsors') }}
    where official_id is not null and sponsor_chamber = 'state_house'
) as k on u.sponsor_name = k.sponsor_name
inner join {{ ref('int_mo_house__member_identity') }} as m
    on
        u.session_code = m.session_code
        and k.official_id = m.person_key
        and ' ' || {{ mogov.name_key('u.sponsor_name') }} || ' ' like '% ' || m.surname_key || ' %'
where u.official_id is null and u.sponsor_chamber = 'state_house'

union all

-- A representative who later moved to the Senate is listed with 200 + the senate district for every session (#646).
-- A sponsor, co-sponsor, handler or House conferee row of a House bill is a House member in that session, so a row
-- still read as state_senate whose name (surname and given name) is a member of that session's House roster, who
-- later held the listed senate seat, was left unmatched when it should be state_house.
select
    u.session_code,
    u.bill,
    u.sponsor_type,
    u.sponsor_name
from {{ ref('fct_bill_sponsors') }} as u
inner join {{ ref('int_mo_house__member_identity') }} as m
    on
        u.session_code = m.session_code
        and ' ' || {{ mogov.name_key('u.sponsor_name') }} || ' ' like '% ' || m.surname_key || ' %'
        and (
            ' ' || {{ mogov.name_key('u.sponsor_name') }} || ' '
            like '% ' || {{ mogov.name_key('m.first_name') }} || ' %'
            or {{ mogov.name_key('u.sponsor_name') }} = {{ mogov.name_key('m.full_name') }}
        )
inner join {{ ref('int_mo_legislators__seats') }} as seat
    on
        seat.chamber = 'upper'
        and m.person_key = seat.person_id
        and u.sponsor_district = seat.district_number
where
    u.sponsor_chamber = 'state_senate'
    and (
        u.sponsor_type in ('Handler', 'HouseConferee')
        or (u.sponsor_type in ('Sponsor', 'Co-Sponsor') and left(u.bill, 1) = 'H')
    )
