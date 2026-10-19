-- The House roll calls taken on each bill: the XML nests them under the bill text version voted on
-- (BillText[].RollCalls[].RollCall[]). rollcall_url is the roll-call PDF, which is the House vote_id.
select
    b.session_code,
    b.bill,
    {{ mogov.json_str('t.value', '$.DocumentName[0]') }} as bill_version,
    {{ mogov.json_str('r.value', '$.RollCallPDF[0]') }} as rollcall_url
from {{ ref('stg_mo_house__bills') }} as b
cross join lateral {{ mogov.json_elements('b.bill_doc', '$.BillText') }} as t
cross join lateral {{ mogov.json_elements('t.value', '$.RollCalls') }} as rc
cross join lateral {{ mogov.json_elements('rc.value', '$.RollCall') }} as r
