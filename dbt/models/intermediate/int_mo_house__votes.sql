-- MO House roll-call votes attributed to people. A PDF token ("SMITH 46", "FOUNTAIN HENDERS",
-- "MR SPEAKER") is matched against that session's House member list: same surname (prefix match for
-- names the PDF truncates) and, when the token carries one, same district. The PDF prints a compound surname by
-- its last word ("REHDER" for Holly Thompson Rehder) and drops a generational suffix ("PRICE" for Wiley Price IV),
-- so those spellings match too. The Speaker comes from the house_speakers seed. Members who left mid-session are
-- missing from that session's (end-of-session) list, so a second pass matches against every session's members; there
-- a person whose dated seat missed the vote date is ruled out even if alone, and one whose seat covered it outranks
-- one with no dated seat. In a session the exact surname beats the suffix-stripped one ("PRICE" is Price not Price IV).
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

-- Matching depends only on the session, the vote date and the token, so it runs once per distinct token and day
-- (about a ninth of the vote rows) and the result is joined back to every vote.
tokens as (
    select distinct
        session_code,
        vote_date,
        member_token,
        token_key,
        token_district
    from votes
),

speaker as (
    select distinct
        v.vote_date,
        s.district_number
    from tokens as v
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

matches as (
    select
        v.session_code,
        v.vote_date,
        v.member_token,
        m.person_key,
        m.party,
        case when v.session_code = m.session_code then 1 else 0 end as same_session,
        -- how the token fits the name: 1 the whole surname (or the truncated start of a long one), 2 the surname
        -- without its generational suffix ("PRICE" for Price IV), 3 the last word of a compound surname
        -- ("HENDERSON" is Henderson, not Fountain Henderson, whom the PDF prints as "FOUNTAIN HENDERS"). The Speaker
        -- is matched by seat, not name.
        case
            when sp.district_number is not null then 1
            when
                v.token_key = m.surname_squashed
                or (length(v.token_key) >= 13 and m.surname_squashed like v.token_key || '%')
                then 1
            when v.token_key = m.surname_unsuffixed then 2
            else 3
        end as name_rank,
        -- 1 unless Open States dates this person's seat and it did not cover the vote date
        max(case when tp.person_id is null or t.person_id is not null then 1 else 0 end) as seat_dated_ok,
        -- 1 when Open States gives this person a seat that covers the vote date
        max(case when t.person_id is not null then 1 else 0 end) as seat_covered
    from tokens as v
    left join speaker as sp on v.vote_date = sp.vote_date and v.member_token = 'MR SPEAKER'
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
    group by 1, 2, 3, 4, 5, 6, 7
),

-- Same-session members rank ahead of other sessions' members (members who left mid-session are only in the latter).
-- Within the same session, a better name fit wins. Outside it a person is a stray namesake unless the dates say
-- otherwise, so a dated seat that missed the vote date rules the person out (even a lone candidate), and a seat that
-- covered the date outranks a person with no dated seat, whatever the name fit.
candidates as (
    select
        session_code,
        vote_date,
        member_token,
        person_key,
        party,
        seat_dated_ok,
        seat_covered,
        (case when same_session = 1 then 1 else 2 end) * 100
        + case when same_session = 1 or seat_covered = 1 then 0 else 10 end
        + name_rank as tier
    from matches
    where same_session = 1 or seat_dated_ok = 1
),

best_tier as (
    select
        session_code,
        vote_date,
        member_token,
        min(tier) as tier
    from candidates
    group by 1, 2, 3
),

best_candidates as (
    select
        c.*,
        max(c.seat_covered) over (partition by c.session_code, c.vote_date, c.member_token) as any_covered
    from candidates as c
    inner join best_tier as b
        on
            c.session_code = b.session_code
            and c.vote_date = b.vote_date
            and c.member_token = b.member_token
            and c.tier = b.tier
),

-- among the candidates, drop those whose dated seat missed the vote date, but only when another candidate's seat
-- covered it; a candidate with no dated seat is never dropped
unique_match as (
    select
        session_code,
        vote_date,
        member_token,
        max(person_key) as person_key,
        max(party) as party
    from best_candidates
    where seat_dated_ok = 1 or any_covered = 0
    group by 1, 2, 3
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
left join unique_match as m
    on v.session_code = m.session_code and v.vote_date = m.vote_date and v.member_token = m.member_token
