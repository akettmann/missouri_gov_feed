-- House committee hearings per bill: one row per hearing notice, for House bills and the Senate bills the House
-- acted on. A bill heard twice, or by two committees, has several rows. Referrals that never got a hearing are
-- bill actions ("Referred: ..."), not rows here.
-- A notice the House lists twice, identical in committee, date, time and room, is one hearing: the earlier copy is
-- is_superseded and names the later one in superseded_by_index. Filter is_superseded = false to count hearings.
-- Notices that differ in time or room on one day are kept as separate hearings (a morning and an afternoon Rules
-- session are two), so a true time change is not flagged here.
with hearings as (
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
        comments,
        lead(hearing_index) over (
            partition by session_code, bill, committee_name, hearing_date, hearing_time, hearing_time_note, location
            order by hearing_index
        ) as superseded_by_index
    from {{ ref('stg_mo_house__bill_hearings') }}
)

select
    *,
    superseded_by_index is not null as is_superseded
from hearings
