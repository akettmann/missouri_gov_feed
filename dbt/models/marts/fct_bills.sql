-- Missouri bills and resolutions per session, with their subject index terms folded into one text column
-- for display; fct_bill_subjects has one row per term for grouping.
--   House bills  the House XML export: titles, current version, last action
--   Senate bills the Senate topical index (regular sessions): its one-line description as the short
--                title; Senate bills filed under no keyword aren't listed there and are missing
--   Senate bills the House XML lists as having reached the House (SenateActList), when the topical index does
--                not list them: every special-session Senate bill (the index covers regular sessions only), with
--                no title, since the XML gives none
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
),

senate_bills as (
    select
        session_code,
        max(session_year) as session_year,
        bill,
        max(description) as short_title,
        max(bill_url) as source_url
    from {{ ref('stg_mo_senate__bill_topics') }}
    where bill like 'S%'
    group by session_code, bill
),

house_listed_senate_bills as (
    select distinct
        a.session_code,
        2000 + {{ dbt.safe_cast('substr(a.session_code, 1, 2)', dbt.type_int()) }} as session_year,
        a.bill
    from {{ ref('stg_mo_house__bill_actions') }} as a
    left join senate_bills as t on a.session_code = t.session_code and a.bill = t.bill
    where a.listed_in = 'senate_act_list' and t.bill is null
),

bills as (
    select
        session_code,
        session_year,
        bill,
        current_bill_string,
        short_title,
        long_title,
        last_action,
        proposed_effective_date,
        source_url
    from {{ ref('stg_mo_house__bills') }}

    union all

    select
        session_code,
        session_year,
        bill,
        cast(null as {{ dbt.type_string() }}) as current_bill_string,
        short_title,
        cast(null as {{ dbt.type_string() }}) as long_title,
        cast(null as {{ dbt.type_string() }}) as last_action,
        cast(null as date) as proposed_effective_date,
        source_url
    from senate_bills

    union all

    select
        session_code,
        session_year,
        bill,
        cast(null as {{ dbt.type_string() }}) as current_bill_string,
        cast(null as {{ dbt.type_string() }}) as short_title,
        cast(null as {{ dbt.type_string() }}) as long_title,
        cast(null as {{ dbt.type_string() }}) as last_action,
        cast(null as date) as proposed_effective_date,
        cast(null as {{ dbt.type_string() }}) as source_url
    from house_listed_senate_bills
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
from bills as b
left join subjects as s on b.session_code = s.session_code and b.bill = s.bill
left join {{ ref('int_bills__status') }} as st on b.session_code = st.session_code and b.bill = st.bill
