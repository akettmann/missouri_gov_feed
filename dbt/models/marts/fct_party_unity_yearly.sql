-- Party-line votes per official, chamber and calendar year of the vote: how many they cast (yea or nay,
-- on a vote where the Republican and Democratic majorities took opposite sides, see
-- int_votes__party_positions) and how many of those went with their own party's majority. The party is the
-- one the official held at the vote (party_at_vote), so a member who switched parties mid-year is counted
-- with each party for the votes cast under it. fct_bias_indicators sums these rows for party_unity_pct, so
-- the lifetime figure and the yearly award figure share one definition. A vote with no date has a null year.
select
    v.official_id,
    v.chamber,
    extract(year from v.vote_date) as vote_year,
    count(*) as party_line_votes,
    sum(
        case
            when
                v.vote_cast
                = case v.party_at_vote when 'Republican' then p.republican_position else p.democratic_position end
                then 1
            else 0
        end
    ) as with_party_votes
from {{ ref('fct_votes') }} as v
inner join {{ ref('int_votes__party_positions') }} as p on v.chamber = p.chamber and v.vote_id = p.vote_id
where
    p.is_party_line
    and v.vote_cast in ('yea', 'nay')
    and v.party_at_vote in ('Republican', 'Democratic')
group by v.official_id, v.chamber, extract(year from v.vote_date)
