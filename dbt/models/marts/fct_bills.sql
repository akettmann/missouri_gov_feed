-- Missouri bills and resolutions per session, with their subject index terms folded into one text column
-- for display; fct_bill_subjects has one row per term for grouping. The bill list is int_bills__list: House bills
-- from the House XML export, Senate bills from the Senate's own bill list (senate.mo.gov, regular and special
-- sessions: every Senate bill, including those under no topical-index keyword; #586), then for a session whose Senate
-- list is not loaded the Senate topical index (regular sessions; bills under no keyword are missing) and the Senate
-- bills the House XML's SenateActList lists that neither has (2024 on).
-- status and outcome come from the actions of both chambers (int_bills__status): the House XML's for House bills and
-- the Senate bills that reached the House, and the Senate's own history (senate.mo.gov; #588) for every Senate bill
-- of a session the mo_senate_bills loader has landed. Null for a Senate bill of an unlanded session that never
-- reached the House (the House's list of Senate bills exists only for 2024 and later), and for a listed Senate bill
-- whose Actions tab was not landed (unknown, not a stage).
-- Each regular session also lists 15 to 17 relistings of the previous session's appropriation bills (status
-- 'relisted for governor message', relisted_from_session_code naming the original's session): the House adds
-- them only to record the governor's Art. IV, s. 27 message. They are rows here but not new bills, so count
-- bills with status <> 'relisted for governor message'; they have no outcome, so outcome counts are unaffected.
with subjects as (
    select
        session_code,
        bill,
        {{ dbt.listagg('subject_name', "'; '", "order by subject_name") }} as subjects
    from {{ ref('int_bills__subjects') }}
    group by session_code, bill
)

select
    b.session_code,
    b.session_year,
    b.bill,
    b.current_bill_string,
    b.short_title,
    b.long_title,
    s.subjects,
    b.last_action,
    st.status,
    st.outcome,
    st.relisted_from_session_code,
    b.proposed_effective_date,
    b.source_url
from {{ ref('int_bills__list') }} as b
left join subjects as s on b.session_code = s.session_code and b.bill = s.bill
left join {{ ref('int_bills__status') }} as st on b.session_code = st.session_code and b.bill = st.bill
