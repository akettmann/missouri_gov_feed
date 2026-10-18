-- One row per current Missouri public official: statewide executives, legislators, congressional
-- delegation, tracked mayors, and state + federal judges.
select
    o.official_id,
    o.full_name,
    o.given_name,
    o.family_name,
    o.party,
    o.level,
    o.office,
    o.office_title,
    o.district,
    o.current_term_start,
    o.current_term_end,
    o.openstates_id,
    o.bioguide_id,
    c.icpsr,
    c.opensecrets_id,
    c.votesmart_id,
    coalesce(c.wikidata_qid, r.wikidata_qid) as wikidata_qid,
    c.senate_lis_id,
    p.email,
    p.image_url,
    p.hometown
from {{ ref('int_officials__current') }} as o
left join {{ ref('stg_congress__legislators') }} as c on o.bioguide_id = c.bioguide_id
left join {{ ref('stg_openstates__people') }} as p on o.openstates_id = p.openstates_id
left join {{ ref('stg_openstates__current_roster') }} as r on o.openstates_id = r.openstates_id
