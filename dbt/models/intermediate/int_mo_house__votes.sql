-- MO House roll-call votes attributed to people. A PDF token ("SMITH 46", "FOUNTAIN HENDERS",
-- "MR SPEAKER") is matched against that session's House member list: same surname (prefix match for
-- names the PDF truncates) and, when the token carries one, same district. The PDF prints a compound surname by
-- its last word ("REHDER" for Holly Thompson Rehder) and drops a generational suffix ("PRICE" for Wiley Price IV),
-- so those spellings match too. The Speaker comes from the house_speakers seed. Members who left mid-session are
-- missing from that session's (end-of-session) list, so a second pass matches against every session's members.
-- Keys ignore spaces ("VANSCHOIACK" = "Van Schoiack"). When several people still fit a token, the Open States seat
-- dates break the tie: a person whose seat did not cover the vote date is dropped if another candidate's did ("EVANS"
-- after Jean Evans left on 2019-02-05 is David Evans). Tokens still matching zero or several people stay
-- unattributed rather than guessed.
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
        replace(surname_key, ' ', '') as surname_squashed,
        replace({{ mogov.surname_key('surname_key') }}, ' ', '') as surname_unsuffixed,
        -- last word of the suffix-less surname: null for a one-word surname
        case
            when {{ mogov.surname_key('surname_key') }} like '% %'
                then replace({{ mogov.regex_replace_all(mogov.surname_key('surname_key'), '^.* ', '') }}, ' ', '')
        end as surname_last_word
    from {{ ref('int_mo_house__member_identity') }}
),

-- the dates Open States gives each House seat holder (person and district), to break ties between same-surname members
house_terms as (
    select
        person_id,
        district_number,
        start_date,
        end_date
    from {{ ref('int_mo_legislators__seats_as_given') }}
    where chamber = 'lower'
),

term_people as (
    select distinct
        person_id,
        district_number
    from house_terms
),

candidates as (
    select
        v.rollcall_url,
        v.member_token,
        m.person_key,
        m.party,
        -- same-session members first; within that, a whole-surname match beats the last word of a compound surname
        -- ("HENDERSON" is Henderson, not Fountain Henderson, whom the PDF prints as "FOUNTAIN HENDERS")
        (case when v.session_code = m.session_code then 1 else 2 end) * 10
        + case when v.token_key = m.surname_last_word and v.token_key <> m.surname_squashed then 2 else 1 end as tier,
        -- 1 unless Open States dates this person's seat and it did not cover the vote date
        max(case when tp.person_id is null or t.person_id is not null then 1 else 0 end) as seat_dated_ok
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
                    v.token_key in (m.surname_squashed, m.surname_unsuffixed, m.surname_last_word)
                    or (length(v.token_key) >= 13 and m.surname_squashed like v.token_key || '%')
                )
                and (v.token_district is null or v.token_district = m.district_number)
            )
    left join term_people as tp on m.person_key = tp.person_id and m.district_number = tp.district_number
    left join house_terms as t
        on
            m.person_key = t.person_id
            and m.district_number = t.district_number
            and v.vote_date between t.start_date and t.end_date
    group by 1, 2, 3, 4, 5
),

best_tier as (
    select
        rollcall_url,
        member_token,
        min(tier) as tier
    from candidates
    group by 1, 2
),

best_candidates as (
    select
        c.*,
        max(c.seat_dated_ok) over (partition by c.rollcall_url, c.member_token) as any_dated_ok
    from candidates as c
    inner join best_tier as b
        on c.rollcall_url = b.rollcall_url and c.member_token = b.member_token and c.tier = b.tier
),

-- among the candidates, drop those whose dated seat missed the vote date, but only when someone else's covered it
unique_match as (
    select
        rollcall_url,
        member_token,
        max(person_key) as person_key,
        max(party) as party
    from best_candidates
    where seat_dated_ok = 1 or any_dated_ok = 0
    group by 1, 2
    having count(distinct person_key) = 1
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
