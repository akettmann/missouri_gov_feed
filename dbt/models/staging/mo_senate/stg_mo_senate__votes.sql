-- One row per (MO Senate journal vote, senator token). Tokens: surname, or "Brown (16)" when two
-- senators share one. The context is the journal sentence introducing the vote.
with src as (
    select
        {{ mogov.json_str('payload', '$.url') }} as journal_url,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.year'), dbt.type_int()) }} as session_year,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.block_index'), dbt.type_int()) }} as block_index,
        {{ mogov.json_str('payload', '$.journal_date') }} as journal_date_text,
        {{ mogov.json_str('payload', '$.context') }} as context,
        {{ mogov.json_str('payload', '$.category') }} as category,
        replace({{ mogov.json_str('payload', '$.name') }}, '’', '''') as senator_token
    from {{ source('mo_senate', 'votes') }}
)

select
    journal_url,
    session_year,
    block_index,
    journal_url || '#vote' || {{ dbt.safe_cast('block_index', dbt.type_string()) }} as vote_id,
    {{ mogov.parse_date(mogov.title_case('journal_date_text'), '%B %d, %Y') }} as vote_date,
    context,
    trim(
        {{ mogov.regex_extract('context', '((?:SS|SCS|HCS|HS)?[ #0-9A-Z]*\\b(?:SB|HB|SJR|HJR|SR|HR|SCR|HCR) [0-9]+)') }}
    )
        as measure,
    senator_token,
    trim({{ mogov.regex_extract('senator_token', '^([^(]+)') }}) as token_name,
    {{ dbt.safe_cast(mogov.regex_extract('senator_token', '\\(([0-9]+)\\)'), dbt.type_int()) }} as token_district,
    case category
        when 'YEAS' then 'yea'
        when 'NAYS' then 'nay'
        when 'Absent' then 'absent'
        when 'Absent with leave' then 'absent with leave'
    end as vote_cast
from src
