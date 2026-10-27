-- House committee hearings per bill: one row per hearing notice, for House bills and the Senate bills the House
-- acted on. A bill heard twice, or by two committees, has several rows. Referrals that never got a hearing are
-- bill actions ("Referred: ..."), not rows here.
select
    session_code,
    session_year,
    bill,
    hearing_index,
    committee_name,
    hearing_date,
    hearing_time,
    hearing_time_note,
    location,
    comments
from {{ ref('stg_mo_house__bill_hearings') }}
