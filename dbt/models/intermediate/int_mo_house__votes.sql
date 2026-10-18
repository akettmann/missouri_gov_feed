-- MO House roll-call votes attributed to people. A PDF token ("SMITH 46", "FOUNTAIN HENDERS",
-- "MR SPEAKER") is matched against that session's House member list: same surname (prefix match for
-- names the PDF truncates) and, when the token carries one, same district. The Speaker comes from the
-- house_speakers seed. Members who left mid-session are missing from that session's (end-of-session)
-- list, so a second pass matches against every session's members. Keys ignore spaces ("VANSCHOIACK" =
-- "Van Schoiack"). Tokens matching zero or several people stay unattributed rather than guessed.
with votes as (
    select
        v.*,
        r.vote_date,
        r.measure,
        r.calendar_item,
        r.sponsor,
        replace({{ mogov.name_key('v.token_name') }}, ' ', '') as token_key
    from {{ ref('stg_mo_house__rollcall_votes') }} as v
    inner join {{ ref('stg_mo_house__rollcalls') }} as r on v.rollcall_url = r.rollcall_url
),

speaker as (
    select
        v.rollcall_url,
        s.district_number
    from votes as v
    inner join {{ ref('house_speakers') }} as s on extract(year from v.vote_date) = s.session_year
    where v.member_token = 'MR SPEAKER'
),

members as (
    select
        *,
        replace(surname_key, ' ', '') as surname_squashed
    from {{ ref('int_mo_house__member_identity') }}
),

candidates as (
    select
        v.rollcall_url,
        v.member_token,
        m.person_key,
        m.party,
        case when v.session_code = m.session_code then 1 else 2 end as tier
    from votes as v
    left join speaker as sp on v.rollcall_url = sp.rollcall_url and v.member_token = 'MR SPEAKER'
    inner join members as m
        on
            (
                v.session_code = m.session_code
                and sp.district_number = m.district_number
            )
            or (
                sp.district_number is null
                and (
                    v.token_key = m.surname_squashed
                    or (length(v.token_key) >= 13 and m.surname_squashed like v.token_key || '%')
                )
                and (v.token_district is null or v.token_district = m.district_number)
            )
),

best_tier as (
    select
        rollcall_url,
        member_token,
        min(tier) as tier
    from candidates
    group by 1, 2
),

unique_match as (
    select
        c.rollcall_url,
        c.member_token,
        max(c.person_key) as person_key,
        max(c.party) as party
    from candidates as c
    inner join best_tier as b
        on c.rollcall_url = b.rollcall_url and c.member_token = b.member_token and c.tier = b.tier
    group by 1, 2
    having count(distinct c.person_key) = 1
)

select
    v.rollcall_url as vote_id,
    'state_house' as chamber,
    v.session_code,
    v.vote_date,
    v.measure,
    v.calendar_item,
    v.sponsor,
    v.member_token,
    m.person_key,
    m.party,
    v.vote_cast,
    v.rollcall_url as source_url
from votes as v
left join unique_match as m on v.rollcall_url = m.rollcall_url and v.member_token = m.member_token
