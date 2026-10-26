-- Every roll-call vote cast by a current member of Missouri's congressional delegation (loaded congresses).
-- Joined on bioguide via Voteview's member file, since congress-legislators lacks ICPSR for newer members.
with members as (
    select distinct
        o.official_id,
        o.full_name,
        m.congress,
        m.chamber,
        m.icpsr
    from {{ ref('dim_official') }} as o
    inner join {{ ref('stg_voteview__members') }} as m on o.bioguide_id = m.bioguide_id
    where o.level = 'federal'
)

select
    m.official_id,
    m.full_name,
    v.congress,
    v.chamber,
    v.rollnumber,
    r.vote_date,
    r.bill_number,
    r.vote_question,
    r.vote_desc,
    r.dtl_desc,
    r.vote_result,
    v.vote_cast,
    'https://voteview.com/rollcall/R' || {{ dbt.concat([
        "case v.chamber when 'House' then 'H' when 'Senate' then 'S' end",
        mogov.zero_pad('v.congress', 3),
        mogov.zero_pad('v.rollnumber', 4),
    ]) }} as source_url
from members as m
inner join {{ ref('stg_voteview__votes') }} as v
    on m.congress = v.congress and m.chamber = v.chamber and m.icpsr = v.icpsr
inner join {{ ref('stg_voteview__rollcalls') }} as r
    on v.congress = r.congress and v.chamber = r.chamber and v.rollnumber = r.rollnumber
where v.vote_cast <> 'not a member'
