-- One row per action on a bill in the House XML export: House bills (BillList) and the Senate bills that reached
-- the House (SenateActList, which lists only their House-side and governor actions, not their Senate history).
-- description is as printed, e.g. "Perfected (H)", "Truly Agreed To and Finally Passed", "Approved by Governor (G)";
-- action_seq orders a bill's actions (the XML's ActivitySequence; missing before 2024). The XML repeats some
-- actions word for word under one Guid (about 1,000 of 138,000, mostly 2017-2018); they are kept once.
with senate_bills as (
    select
        {{ mogov.json_str('l.payload', '$.session_code') }} as session_code,
        b.value as bill_doc
    from {{ source('mo_house', 'lists') }} as l
    -- one wrapper element per file, holding every Senate bill in its BillInformation array
    cross join lateral {{ mogov.json_elements('l.payload', '$.doc.SenateBillsWithHouseActions') }} as s
    cross join lateral {{ mogov.json_elements('s.value', '$.BillInformation') }} as b
    where {{ mogov.json_str('l.payload', '$.list') }} = 'SENATEACTLIST'
),

bills as (
    select
        session_code,
        bill,
        'house_bill_list' as listed_in,
        bill_doc
    from {{ ref('stg_mo_house__bills') }}

    union all

    select
        session_code,
        {{ mogov.json_str('bill_doc', '$.BillNumber[0]') }} as bill,
        'senate_act_list' as listed_in,
        bill_doc
    from senate_bills
)

select distinct
    b.session_code,
    b.bill,
    b.listed_in,
    {{ dbt.safe_cast(mogov.json_str('a.value', '$.ActivitySequence[0]'), dbt.type_int()) }} as action_seq,
    {{ dbt.safe_cast(mogov.json_str('a.value', '$.PubDate[0]'), 'date') }} as action_date,
    trim({{ mogov.json_str('a.value', '$.Description[0]') }}) as description,
    {{ mogov.json_str('a.value', '$.Guid[0]') }} as action_guid
from bills as b
cross join lateral {{ mogov.json_elements('b.bill_doc', '$.Action') }} as a
