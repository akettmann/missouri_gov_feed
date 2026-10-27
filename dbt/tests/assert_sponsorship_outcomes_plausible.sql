-- Sanity check: across the whole House, the share of decided HB/HJR primary-sponsored bills that became law in a
-- finished session with at least 400 decided bills. Seen 0.5% (2023) to 2.1% (2026); the bounds 0.1% to 25% catch a
-- numerator that is always 0 (a status that never matches) or that counts nearly every bill (the failed or pending
-- outcomes leaking in). Bills that became law all passed the House, so passed-house can't be below became-law.
select
    session_code,
    sum(bills_decided) as bills_decided,
    sum(bills_became_law) as bills_became_law,
    sum(bills_passed_house) as bills_passed_house
from {{ ref('fct_sponsorship_outcomes') }}
where is_session_over
group by session_code
having
    sum(bills_decided) >= 400
    and (
        sum(bills_became_law) < 0.001 * sum(bills_decided)
        or sum(bills_became_law) > 0.25 * sum(bills_decided)
        or sum(bills_passed_house) < sum(bills_became_law)
    )
