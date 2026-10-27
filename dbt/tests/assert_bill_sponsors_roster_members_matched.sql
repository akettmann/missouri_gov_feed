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
