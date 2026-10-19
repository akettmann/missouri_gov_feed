-- Party-line votes where the official voted against their own party's majority: the votes behind a
-- party_unity_pct below 100. Same inputs as the indicator (fct_votes + int_votes__party_positions), so the
-- rows here are exactly the "against" side of that percentage.
select
    v.official_id,
    v.full_name,
    v.chamber,
    v.session_code,
    v.vote_id,
    v.vote_date,
    v.measure,
    v.vote_description,
    v.party_at_vote,
    v.vote_cast,
    case v.party_at_vote when 'Republican' then p.republican_position else p.democratic_position end
        as party_position,
    case v.party_at_vote when 'Republican' then p.democratic_position else p.republican_position end
        as other_party_position,
    p.republican_yea,
    p.republican_nay,
    p.democratic_yea,
    p.democratic_nay,
    v.source_url
from {{ ref('fct_votes') }} as v
inner join {{ ref('int_votes__party_positions') }} as p on v.chamber = p.chamber and v.vote_id = p.vote_id
where
    p.is_party_line
    and v.vote_cast in ('yea', 'nay')
    and v.party_at_vote in ('Republican', 'Democratic')
    and v.vote_cast
    <> case v.party_at_vote when 'Republican' then p.republican_position else p.democratic_position end
