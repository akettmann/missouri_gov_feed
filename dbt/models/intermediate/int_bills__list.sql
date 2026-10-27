-- Every Missouri bill and resolution per session, from the places that list them; fct_bills and fct_vote_bills
-- both read this one list so a bill cannot be in one and not the other. Re-listed appropriation bills are kept here
-- (they are House bills; int_bills__status marks them).
--   House bills  the House XML export: titles, current version, last action
--   Senate bills the Senate's own bill list (senate.mo.gov, regular and special sessions; mo_senate_bills loader,
--                #586): complete, including bills filed under no topical-index keyword (2018 SB 975 and 1024) and
--                bills that never left the Senate. Its one-line description is the short title. It covers the sessions
--                the loader's window reached; for a session it has not landed, the next two sources stand in
--   Senate bills the Senate topical index (regular sessions) of a session the Senate list has no rows for: its
--                one-line description as the short title; bills filed under no keyword are missing
--   Senate bills the House XML's SenateActList lists as having reached the House (2024 on), when neither of the above
--                lists them, with the titles, version, last action and effective date the XML gives. Senate bills of
--                older special sessions are missing without the Senate list (#237).
-- source_url is the Senate's bill link, else the bill's page on house.mo.gov from the House XML (House bills and
-- the House-listed Senate bills). A column a source does not give is null.
with senate_list_bills as (
    select
        session_code,
        max(session_year) as session_year,
        bill,
        max(short_title) as short_title,
        max(bill_url) as source_url
    from {{ ref('stg_mo_senate__bills') }}
    where session_code is not null
    group by session_code, bill
),

senate_index_bills as (
    select
        t.session_code,
        max(t.session_year) as session_year,
        t.bill,
        max(t.description) as short_title,
        max(t.bill_url) as source_url
    from {{ ref('stg_mo_senate__bill_topics') }} as t
    left join (select distinct session_code from senate_list_bills) as covered
        on t.session_code = covered.session_code
    where t.bill like 'S%' and covered.session_code is null
    group by t.session_code, t.bill
),

senate_bills as (
    select * from senate_list_bills
    union all
    select * from senate_index_bills
)

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
    a.session_code,
    a.session_year,
    a.bill,
    a.current_bill_string,
    a.short_title,
    a.long_title,
    a.last_action,
    a.proposed_effective_date,
    a.source_url
from {{ ref('stg_mo_house__senate_act_bills') }} as a
left join senate_bills as t on a.session_code = t.session_code and a.bill = t.bill
where t.bill is null
