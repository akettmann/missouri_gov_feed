-- The House roll calls taken on each bill: the XML nests them under the bill text version voted on (amendment
-- roll calls are left out). rollcall_url is the roll-call PDF, which is the House vote_id.
select
    b.session_code,
    b.bill,
    r.parent_name as bill_version,
    r.rollcall_pdf as rollcall_url
from {{ source('mo_house', 'xml_bills') }} as b
inner join {{ source('mo_house', 'xml_bill_rollcalls') }} as r
    on b.session_code = r.session_code and b.file_name = r.file_name
where r.parent_kind = 'text'
