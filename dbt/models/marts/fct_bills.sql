-- Missouri bills and resolutions per session, with their subject index terms folded into one text column
-- for display; fct_bill_subjects has one row per term for grouping. The bill list is int_bills__list: House bills
-- from the House XML export, Senate bills from the Senate topical index (regular sessions; Senate bills filed under
-- no keyword are missing) and the Senate bills the House XML's SenateActList lists that the index does not (the
-- special-session Senate bills, 2024 on; older special sessions' Senate bills are missing, #237).
-- status and outcome come from the House XML's actions (int_bills__status): null for Senate bills that never
-- reached the House, whose actions aren't loaded: every Senate bill before 2024, since the House's list of Senate
-- bills exists only for 2024 and later.
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
