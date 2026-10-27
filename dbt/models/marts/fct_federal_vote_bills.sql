-- Which federal bill each Voteview roll call was taken on (not always its passage: recommit, previous question,
-- cloture, tabling and similar procedural votes are included; amendment votes are not, #738),
-- from the roll calls the GovInfo BILLSTATUS actions cite.
-- BILLSTATUS names a roll call by (congress, chamber, session, roll number), where the roll number is the chamber
-- clerk's, restarting each session; Voteview's own `rollnumber` runs across the Congress, so the join is on its
-- `clerk_rollnumber` (with its `session`). Voteview's `bill_number` text (e.g. "HR3746") is kept beside it for
-- comparison but is not what links the two.
-- Grain: (congress, chamber, rollnumber, bill_id). A roll call can cite more than one bill (a motion covering
-- several measures) and a bill can have many roll calls. The same roll call appears under the chamber's own action
-- and the Library of Congress copy of it, so cited votes are de-duplicated first.
-- Only roll calls both sources know are listed; the BILLSTATUS side may cover fewer bills than Congress handled
-- (the loaded Congresses and bill types), so a roll call missing here is "no bill found", not "no bill".
with cited as (
    select distinct
        bill_id,
        congress,
        chamber,
        session_number,
        roll_number
    from {{ ref('stg_govinfo_billstatus__recorded_votes') }}
    where
        roll_number is not null
        and session_number is not null
)

select
    r.congress,
    r.chamber,
    r.rollnumber,
    r.session,
    r.clerk_rollnumber,
    r.vote_date,
    b.bill_id,
    b.bill_type,
    b.bill_number as bill_no,
    b.title as bill_title,
    b.legislation_url,
    r.bill_number as voteview_bill_number,
    r.vote_question,
    r.vote_result,
    r.yea_count,
    r.nay_count,
    'https://voteview.com/rollcall/R' || {{ dbt.concat([
        "case r.chamber when 'House' then 'H' when 'Senate' then 'S' end",
        mogov.zero_pad('r.congress', 3),
        mogov.zero_pad('r.rollnumber', 4),
    ]) }} as source_url
from cited as c
inner join {{ ref('stg_voteview__rollcalls') }} as r
    on
        c.congress = r.congress
        and c.chamber = r.chamber
        and c.session_number = r.session
        and c.roll_number = r.clerk_rollnumber
inner join {{ ref('stg_govinfo_billstatus__bills') }} as b on c.bill_id = b.bill_id
