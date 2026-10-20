-- Sanity check: votes listing more members than the chamber has seats (House 163, Senate 34). A larger count
-- means a parsing bug: one person split in two ("Thompson Rehder") or a heading read as a name ("Vacancies").
select
    'state_house' as chamber,
    rollcall_url as vote_id,
    count(*) as members
from {{ ref('stg_mo_house__rollcall_votes') }}
group by rollcall_url
having count(*) > 163

union all

select
    'state_house' as chamber,
    rollcall_url as vote_id,
    total_yes + total_no as members
from {{ ref('stg_mo_house__rollcalls') }}
where total_yes + total_no > 163

union all

select
    'state_senate' as chamber,
    vote_id,
    count(*) as members
from {{ ref('stg_mo_senate__votes') }}
group by vote_id
having count(*) > 34
