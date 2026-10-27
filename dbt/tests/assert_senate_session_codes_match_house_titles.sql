-- Evidence check for the mo_senate_session_codes seed: the House's SenateActList names, under the House session
-- code, the Senate bills that reached the House, and its long title is the Senate's own description for most of them
-- (2024 to 2026 regular sessions: 51% to 74% identical, the rest reworded after amendment; 2025's special session
-- 253: 3 of 3). A seed code pointing at the wrong House session matches about none. Fails a mapped session with at
-- least 3 bills in both lists where under 30% of titles match.
with joined as (
    select
        s.session_code,
        case when lower(trim(s.short_title)) = lower(trim(h.long_title)) then 1 else 0 end as same_title
    from {{ ref('stg_mo_senate__bills') }} as s
    inner join {{ ref('stg_mo_house__senate_act_bills') }} as h
        on s.session_code = h.session_code and s.bill = h.bill
)

select
    session_code,
    count(*) as bills_in_both,
    sum(same_title) as same_titles
from joined
group by session_code
having count(*) >= 3 and sum(same_title) < 0.3 * count(*)
