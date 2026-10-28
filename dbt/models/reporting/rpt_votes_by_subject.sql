-- How each official voted on bills by subject: recorded votes (fct_votes) linked to bills (fct_vote_bills) and
-- the bills' subjects (fct_bill_subjects: House subject index, Senate topics). A roll call on several bills
-- with the same subject counts once, so counts are distinct roll calls. Subject names come from two indexes
-- (subject_source) and aren't merged across them.
-- Subjects are deduped per roll call before joining the ~500k votes, so the vote counts are plain sums over one
-- row per (official, roll call, subject); count(distinct vote_id) over the full vote x bill x subject fan-out
-- needed ~1.5GB and ran out of memory in the build.
with bill_roll_call_subjects as (
    select
        vb.chamber,
        vb.vote_id,
        vb.session_code,
        vb.bill,
        s.subject_name,
        s.subject_source
    from {{ ref('fct_vote_bills') }} as vb
    inner join {{ ref('fct_bill_subjects') }} as s
        on vb.session_code = s.session_code and vb.bill = s.bill
),

roll_call_subjects as (
    select distinct
        chamber,
        vote_id,
        subject_name,
        subject_source
    from bill_roll_call_subjects
),

-- fct_votes is one row per (official, chamber, vote_id), so each row here is one roll call
vote_counts as (
    select
        v.official_id,
        v.chamber,
        rcs.subject_name,
        rcs.subject_source,
        count(*) as roll_calls,
        sum(case when v.vote_cast = 'yea' then 1 else 0 end) as yea,
        sum(case when v.vote_cast = 'nay' then 1 else 0 end) as nay,
        sum(case when v.vote_cast not in ('yea', 'nay') then 1 else 0 end) as other
    from {{ ref('fct_votes') }} as v
    inner join roll_call_subjects as rcs
        on v.chamber = rcs.chamber and v.vote_id = rcs.vote_id
    group by v.official_id, v.chamber, rcs.subject_name, rcs.subject_source
),

bill_counts as (
    select
        v.official_id,
        v.chamber,
        b.subject_name,
        b.subject_source,
        count(distinct b.session_code || ':' || b.bill) as bills,
        min(b.session_code) as first_session,
        max(b.session_code) as last_session
    from {{ ref('fct_votes') }} as v
    inner join bill_roll_call_subjects as b
        on v.chamber = b.chamber and v.vote_id = b.vote_id
    group by v.official_id, v.chamber, b.subject_name, b.subject_source
)

select
    vc.official_id,
    vc.chamber,
    vc.subject_name,
    vc.subject_source,
    cast(vc.roll_calls as {{ dbt.type_bigint() }}) as roll_calls,
    cast(vc.yea as {{ dbt.type_bigint() }}) as yea,
    cast(vc.nay as {{ dbt.type_bigint() }}) as nay,
    cast(vc.other as {{ dbt.type_bigint() }}) as other,
    cast(bc.bills as {{ dbt.type_bigint() }}) as bills,
    bc.first_session,
    bc.last_session
from vote_counts as vc
inner join bill_counts as bc
    on
        vc.official_id = bc.official_id
        and vc.chamber = bc.chamber
        and vc.subject_name = bc.subject_name
        and vc.subject_source = bc.subject_source
