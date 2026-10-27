-- Sanity check: a Senate bill whose history says "Truly Agreed To and Finally Passed" (2017 sessions on) has a
-- "Truly Agreed to and Finally Passed" text version on its bill page, the enrolled text. Only bills that have some
-- text version landed are checked: a bill whose tab the loader skipped (a rejected fragment, retried next run) has
-- no text rows at all, and is not a gap in the page. A bill with texts but no truly agreed one means the text parser
-- lost a row or the page renamed the version.
with truly_agreed as (
    select distinct
        session_code,
        bill
    from {{ ref('stg_mo_senate__bill_actions') }}
    where action = 'Truly Agreed To and Finally Passed' and session_year >= 2017 and session_code is not null
),

texts as (
    select
        session_code,
        bill,
        max(case when lower(version) like 'truly agreed%' then 1 else 0 end) as has_truly_agreed_text
    from {{ ref('stg_mo_senate__bill_texts') }}
    group by session_code, bill
)

select
    t.session_code,
    t.bill
from truly_agreed as ta
inner join texts as t on ta.session_code = t.session_code and ta.bill = t.bill
where t.has_truly_agreed_text = 0
