-- Each party's majority position on every recorded vote, counted over every member who voted
-- (int_votes__member_votes), not only the officials tracked today. A party's position is the side most of
-- its yea/nay voters took; a tie has no position. A party-line vote is one where the Republican and
-- Democratic majorities took opposite sides. vote_id and chamber match fct_votes.
with counts as (
    select
        chamber,
        vote_id,
        sum(case when party = 'Republican' and vote_cast = 'yea' then 1 else 0 end) as republican_yea,
        sum(case when party = 'Republican' and vote_cast = 'nay' then 1 else 0 end) as republican_nay,
        sum(case when party = 'Democratic' and vote_cast = 'yea' then 1 else 0 end) as democratic_yea,
        sum(case when party = 'Democratic' and vote_cast = 'nay' then 1 else 0 end) as democratic_nay
    from {{ ref('int_votes__member_votes') }}
    where vote_cast in ('yea', 'nay')
    group by chamber, vote_id
),

positions as (
    select
        *,
        case
            when republican_yea > republican_nay then 'yea'
            when republican_nay > republican_yea then 'nay'
        end as republican_position,
        case
            when democratic_yea > democratic_nay then 'yea'
            when democratic_nay > democratic_yea then 'nay'
        end as democratic_position
    from counts
)

select
    chamber,
    vote_id,
    republican_yea,
    republican_nay,
    democratic_yea,
    democratic_nay,
    republican_position,
    democratic_position,
    coalesce(republican_position <> democratic_position, false) as is_party_line
from positions
