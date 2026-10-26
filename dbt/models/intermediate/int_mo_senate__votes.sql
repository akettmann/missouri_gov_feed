-- MO Senate journal votes attributed to people: the senator serving on the vote date with a matching
-- surname (and district, when the journal adds one to disambiguate), by the dates Open States gives the seat
-- (int_mo_legislators__seats_as_given; int_mo_legislators__seats re-dates Senate terms from these votes). Ambiguous
-- tokens stay unattributed.
with votes as (
    select
        *,
        {{ mogov.name_key('token_name') }} as token_key
    from {{ ref('stg_mo_senate__votes') }}
),

candidates as (
    select
        v.vote_id,
        v.senator_token,
        seat.person_id as person_key,
        seat.party
    from votes as v
    inner join {{ ref('int_mo_legislators__seats_as_given') }} as seat
        on
            seat.chamber = 'upper'
            and v.vote_date between seat.start_date and seat.end_date
            and (v.token_key = seat.surname_key or v.token_key like '% ' || seat.surname_key)
            and (v.token_district is null or v.token_district = seat.district_number)
),

unique_match as (
    select
        vote_id,
        senator_token,
        max(person_key) as person_key,
        max(party) as party
    from candidates
    group by 1, 2
    having count(distinct person_key) = 1
)

select
    v.vote_id,
    'state_senate' as chamber,
    {{ dbt.safe_cast('v.session_year', dbt.type_string()) }} as session_code,
    v.vote_date,
    v.measure,
    cast(null as {{ dbt.type_string() }}) as calendar_item,
    cast(null as {{ dbt.type_string() }}) as sponsor,
    v.senator_token as member_token,
    m.person_key,
    m.party,
    v.vote_cast,
    v.context,
    v.journal_url as source_url
from votes as v
left join unique_match as m on v.vote_id = m.vote_id and v.senator_token = m.senator_token
