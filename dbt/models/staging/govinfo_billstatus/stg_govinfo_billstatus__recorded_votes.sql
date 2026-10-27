-- Roll calls cited by federal bill actions in the GovInfo BILLSTATUS bulk XML, one row per (bill, action, roll call).
-- The same roll call is cited by the chamber's own action and its Library of Congress copy, so it can appear twice
-- for a bill; (congress, chamber, session_number, roll_number) identifies the vote and links to Voteview's roll calls.
select
    {{ mogov.json_str('payload', '$.bill_id') }} as bill_id,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.action_position'), dbt.type_int()) }} as action_position,
    {{ mogov.json_str('payload', '$.chamber') }} as chamber,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.congress'), dbt.type_int()) }} as congress,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.session_number'), dbt.type_int()) }} as session_number,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.roll_number'), dbt.type_int()) }} as roll_number,
    {{ dbt.safe_cast("substring(" ~ mogov.json_str('payload', '$.vote_date') ~ ", 1, 10)", 'date') }} as vote_date,
    {{ mogov.json_str('payload', '$.url') }} as vote_url,
    source_url
from {{ source('govinfo_billstatus', 'recorded_votes') }}
