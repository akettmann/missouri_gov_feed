-- One row per action in a Senate bill's history on senate.mo.gov (both chambers, enrollment and the governor),
-- newest first as served: action_index 0 is the top row. The wording is the Senate's own ("S First Read",
-- "Second Read and Referred S Government Efficiency Committee"), not the House's. journal_ref names the journal
-- page that records the action (it can name both chambers, "H2291 / S1216") and journal_url links the PDF page.
-- session_code is the House's code for the session (seed mo_senate_session_codes), null for a session with no
-- seed row.
with src as (
    select
        {{ dbt.safe_cast(mogov.json_str('payload', '$.year'), dbt.type_int()) }} as session_year,
        {{ mogov.json_str('payload', '$.session_type') }} as session_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.bill_id'), dbt.type_int()) }} as bill_id,
        {{ mogov.json_str('payload', '$.bill') }} as bill,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.action_index'), dbt.type_int()) }} as action_index,
        {{ mogov.json_str('payload', '$.action_date') }} as action_date_text,
        {{ mogov.json_str('payload', '$.action') }} as action,
        {{ mogov.json_str('payload', '$.journal_ref') }} as journal_ref,
        {{ mogov.json_str('payload', '$.journal_url') }} as journal_url
    from {{ source('mo_senate', 'bill_actions') }}
)

select
    src.session_year,
    src.session_type,
    codes.house_session_code as session_code,
    src.bill_id,
    src.bill,
    src.action_index,
    {{ mogov.parse_date('src.action_date_text', '%m/%d/%Y') }} as action_date,
    src.action_date_text,
    src.action,
    src.journal_ref,
    src.journal_url
from src
left join {{ ref('mo_senate_session_codes') }} as codes
    on src.session_year = codes.session_year and src.session_type = codes.session_type
