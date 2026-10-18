-- Voting history for current officials: Missouri House (roll-call PDFs), Missouri Senate (journals) and
-- Congress (Voteview). Includes votes from earlier offices, e.g. a senator's House votes.
with state_votes as (
    select
        vote_id,
        chamber,
        session_code,
        vote_date,
        measure,
        calendar_item as vote_description,
        person_key,
        party,
        vote_cast,
        source_url
    from {{ ref('int_mo_house__votes') }}
    union all
    select
        vote_id,
        chamber,
        session_code,
        vote_date,
        measure,
        context as vote_description,
        person_key,
        party,
        vote_cast,
        source_url
    from {{ ref('int_mo_senate__votes') }}
)

select
    o.official_id,
    o.full_name,
    v.chamber,
    v.session_code,
    v.vote_id,
    v.vote_date,
    v.measure,
    v.vote_description,
    v.vote_cast,
    v.party as party_at_vote,
    v.source_url
from state_votes as v
inner join {{ ref('dim_official') }} as o on v.person_key = o.official_id

union all

select
    f.official_id,
    f.full_name,
    case f.chamber when 'House' then 'us_house' else 'us_senate' end as chamber,
    {{ dbt.safe_cast('f.congress', dbt.type_string()) }} as session_code,
    f.chamber || '-' || {{ dbt.safe_cast('f.congress', dbt.type_string()) }} || '-'
    || {{ dbt.safe_cast('f.rollnumber', dbt.type_string()) }} as vote_id,
    f.vote_date,
    f.bill_number as measure,
    coalesce(f.vote_desc, f.vote_question) as vote_description,
    f.vote_cast,
    o.party as party_at_vote,
    f.source_url
from {{ ref('fct_federal_votes') }} as f
inner join {{ ref('dim_official') }} as o on f.official_id = o.official_id
