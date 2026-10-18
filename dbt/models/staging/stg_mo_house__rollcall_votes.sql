-- One row per (MO House roll call, member token). Tokens: "SMITH 46" (district when surnames collide),
-- "FOUNTAIN HENDERS" (truncated to ~16 chars), "MR SPEAKER".
with src as (
    select
        {{ mogov.json_str('payload', '$.url') }} as rollcall_url,
        {{ mogov.json_str('payload', '$.session_code') }} as session_code,
        {{ mogov.json_str('payload', '$.vote_code') }} as vote_code,
        {{ mogov.json_str('payload', '$.member_token') }} as member_token
    from {{ source('raw', 'mo_house_rollcall_votes') }}
)

select
    rollcall_url,
    session_code,
    member_token,
    trim({{ mogov.regex_extract('member_token', '^(.*?)( [0-9]+)?$') }}) as token_name,
    {{ dbt.safe_cast(mogov.regex_extract('member_token', ' ([0-9]+)$'), dbt.type_int()) }} as token_district,
    case vote_code
        when 'Y' then 'yea'
        when 'N' then 'nay'
        when 'P' then 'present'
        when '@' then 'absent'
    end as vote_cast
from src
