-- One row per MO House roll call (parsed PDF header). The line after "Roll Call : N" names the measure
-- (e.g. "HCS HB 10"); the next lines carry the sponsor and a description.
-- Roll calls dated outside their session's year are dropped (#430): the House leaves the previous session's
-- PDFs in the bills171/rollcalls directory (the 2016 session's, numbered by 2016 session day), and the loader's
-- probe runs on past the last 2017 roll call of a day into them. 415 votes dated 2016 sat under session 171,
-- none linked from the bill XML. They belong to session 161, which is not loaded. Raw keeps them.
with src as (
    select
        {{ mogov.json_str('payload', '$.url') }} as rollcall_url,
        {{ mogov.json_str('payload', '$.session_code') }} as session_code,
        {{ mogov.json_str('payload', '$.session_day') }} as session_day,
        {{ mogov.json_str('payload', '$.rollcall_number') }} as rollcall_number,
        {{ mogov.json_str('payload', '$.vote_date') }} as vote_date_text,
        {{ mogov.json_str('payload', '$.text') }} as header_text,
        {{ mogov.json_str('payload', '$.totals.Yes') }} as total_yes,
        {{ mogov.json_str('payload', '$.totals.No') }} as total_no,
        {{ mogov.json_str('payload', '$.error') }} as load_error
    from {{ source('mo_house', 'rollcalls') }}
),

parsed as (
    select
        rollcall_url,
        session_code,
        {{ dbt.safe_cast('session_day', dbt.type_int()) }} as session_day,
        {{ dbt.safe_cast('rollcall_number', dbt.type_int()) }} as rollcall_number,
        {{ mogov.parse_date('vote_date_text', '%m/%d/%Y') }} as vote_date,
        trim({{ mogov.regex_extract('header_text', 'Session Day *: *[0-9]+ +([A-Z][^\n]*?) +Date') }}) as calendar_item,
        trim({{ mogov.regex_extract('header_text', 'Roll Call *: *[0-9]+ +([^\n]+)') }}) as measure,
        trim({{ mogov.regex_extract('header_text', '\n *([A-Z][A-Z .\'-]+ \\([0-9]{3}\\)) *\n') }}) as sponsor,
        {{ dbt.safe_cast('total_yes', dbt.type_int()) }} as total_yes,
        {{ dbt.safe_cast('total_no', dbt.type_int()) }} as total_no
    from src
    where load_error is null
)

select *
from parsed
-- a roll call whose date didn't parse is kept (null passes); session_code's first two digits are the year
where
    vote_date is null
    or extract(year from vote_date) = 2000 + {{ dbt.safe_cast("substring(session_code, 1, 2)", dbt.type_int()) }}
