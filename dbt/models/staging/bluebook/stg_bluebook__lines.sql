-- Missouri Official Manual text, one row per extracted line, in reading order per chapter.
select
    {{ mogov.json_str('payload', '$.edition') }} as edition,
    {{ mogov.json_str('payload', '$.chapter') }} as chapter,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.page'), dbt.type_int()) }} as page,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.column'), dbt.type_int()) }} as page_column,
    {{ dbt.safe_cast(mogov.json_str('payload', '$.line_no'), dbt.type_int()) }} as line_no,
    {{ mogov.json_str('payload', '$.text') }} as line_text,
    {{ mogov.json_str('payload', '$.url') }} as source_url
from {{ source('bluebook', 'lines') }}
