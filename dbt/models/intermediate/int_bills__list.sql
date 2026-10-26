-- Every Missouri bill and resolution per session, from the three places that list them; fct_bills and fct_vote_bills
-- both read this one list so a bill cannot be in one and not the other. Re-listed appropriation bills are kept here
-- (they are House bills; int_bills__status marks them).
--   House bills  the House XML export: titles, current version, last action
--   Senate bills the Senate topical index (regular sessions): its one-line description as the short title; Senate
--                bills filed under no keyword aren't listed there and are missing
--   Senate bills the House XML's SenateActList lists as having reached the House (2024 on), when the topical index
--                does not list them: the special-session Senate bills (the index covers regular sessions only), with
--                the titles, version, last action and effective date the XML gives. Senate bills of older special
--                sessions are missing (#237).
-- source_url is the Senate index's bill link, else the bill's page on house.mo.gov from the House XML (House bills and
-- the House-listed Senate bills). A column a source does not give is null.
with senate_index_bills as (
    select
        session_code,
        max(session_year) as session_year,
        bill,
        max(description) as short_title,
        max(bill_url) as source_url
    from {{ ref('stg_mo_senate__bill_topics') }}
    where bill like 'S%'
    group by session_code, bill
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
from senate_index_bills

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
left join senate_index_bills as t on a.session_code = t.session_code and a.bill = t.bill
where t.bill is null
