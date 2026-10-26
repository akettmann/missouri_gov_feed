-- One row per action on a bill in the House XML export: House bills (BillList) and the Senate bills that reached
-- the House (SenateActList, which lists only their House-side and governor actions, not their Senate history).
-- description is as printed, e.g. "Perfected (H)", "Truly Agreed To and Finally Passed", "Approved by Governor (G)";
-- action_seq orders a bill's actions (the XML's ActivitySequence; missing before 2024). The XML repeats some
-- actions word for word under one Guid (about 1,000 of 138,000, mostly 2017-2018); they are kept once.
select distinct
    b.session_code,
    b.bill,
    'house_bill_list' as listed_in,
    a.activity_sequence as action_seq,
    a.pub_date as action_date,
    a.description,
    a.guid as action_guid
from {{ source('mo_house', 'xml_bill_actions') }} as a
inner join {{ source('mo_house', 'xml_bills') }} as b
    on a.session_code = b.session_code and a.file_name = b.file_name

union all

select distinct
    session_code,
    bill,
    'senate_act_list' as listed_in,
    activity_sequence as action_seq,
    pub_date as action_date,
    description,
    guid as action_guid
from {{ source('mo_house', 'xml_senate_act_actions') }}
