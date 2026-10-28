-- The Congressional Research Service legislative subject terms of each federal bill a Missouri member of Congress
-- sponsored or cosponsored: one row per (member, bill, role, subject), the grain of fct_federal_sponsorship times the
-- bill's subjects. Answers "what topics does this official's name go on". A bill's one broader policy_area is in
-- fct_federal_sponsorship; subjects are many per bill, and CRS tags a bill only after introduction, so a bill that
-- is not tagged yet (many recent bills) has no row here, which is not "no topic".
select
    s.official_id,
    s.bioguide_id,
    s.role,
    s.bill_id,
    s.congress,
    sub.subject,
    sub.source_url
from {{ ref('fct_federal_sponsorship') }} as s
inner join {{ ref('stg_govinfo_billstatus__subjects') }} as sub on s.bill_id = sub.bill_id
