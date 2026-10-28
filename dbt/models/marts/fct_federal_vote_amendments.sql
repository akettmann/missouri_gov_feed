-- Which federal amendment each Voteview roll call decided, from the roll calls the GovInfo BILLSTATUS amendment
-- actions cite, and the bill the amendment was filed to. Sibling of fct_federal_vote_bills, kept apart on purpose:
-- that model answers "how did the chamber vote on this bill" (passage, the bill's own questions), and an
-- amendment roll call is a vote on a part of it, so mixing them would make a bill's vote list read as a pile of
-- floor amendments. Same key as there: BILLSTATUS names a roll call by (congress, chamber, session, clerk roll
-- number) and Voteview's `clerk_rollnumber` with its `session` is the join.
-- Grain: (congress, chamber, rollnumber, amendment_id). An amendment can have several roll calls (agreeing to it,
-- then a motion to table or reconsider) and a roll call can cite more than one amendment; the chamber's own action
-- and the Library of Congress copy of it cite the same roll call, so cited votes are de-duplicated first.
-- Only roll calls both sources know are listed; a roll call missing here is "no amendment found", not "no amendment".
with cited as (
    select distinct
        amendment_id,
        congress,
        chamber,
        session_number,
        roll_number
    from {{ ref('stg_govinfo_billstatus__amendment_recorded_votes') }}
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
    a.amendment_id,
    a.amendment_type,
    a.amendment_number,
    a.purpose as amendment_purpose,
    a.description as amendment_description,
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
inner join {{ ref('stg_govinfo_billstatus__amendments') }} as a on c.amendment_id = a.amendment_id
inner join {{ ref('stg_govinfo_billstatus__bills') }} as b on a.bill_id = b.bill_id
