-- Every recorded vote by every member, tracked official or not: MO House roll calls and MO Senate journals
-- (member_key is the attributed person, else the printed token) and Congress from the loaded Voteview files
-- (member_key is the ICPSR id). Chamber-wide figures (party majorities, chamber attendance) count from here,
-- so they don't depend on who holds office today. vote_id, chamber and session_code match fct_votes.
select
    chamber,
    session_code,
    vote_id,
    coalesce(person_key, 'token:' || member_token) as member_key,
    {{ mogov.normalize_party('party') }} as party,
    vote_cast
from {{ ref('int_mo_house__votes') }}

union all

select
    chamber,
    session_code,
    vote_id,
    coalesce(person_key, 'token:' || member_token) as member_key,
    {{ mogov.normalize_party('party') }} as party,
    vote_cast
from {{ ref('int_mo_senate__votes') }}

union all

select
    case v.chamber when 'House' then 'us_house' when 'Senate' then 'us_senate' end as chamber,
    {{ dbt.safe_cast('v.congress', dbt.type_string()) }} as session_code,
    v.chamber || '-' || {{ dbt.safe_cast('v.congress', dbt.type_string()) }} || '-'
    || {{ dbt.safe_cast('v.rollnumber', dbt.type_string()) }} as vote_id,
    'icpsr:' || {{ dbt.safe_cast('v.icpsr', dbt.type_string()) }} as member_key,
    -- Voteview party codes: 100 Democratic, 200 Republican (others are independents and minor parties)
    case m.party_code when 100 then 'Democratic' when 200 then 'Republican' end as party,
    v.vote_cast
from {{ ref('stg_voteview__votes') }} as v
inner join {{ ref('stg_voteview__members') }} as m
    on v.congress = m.congress and v.chamber = m.chamber and v.icpsr = m.icpsr
