-- One row per RSMo chapter (the Revisor's table of contents). title_numeral is the title's roman numeral
-- ("I"), title_name the rest of its heading. Chapter numbers are text: a few carry a letter.
with src as (
    select
        {{ mogov.json_str('payload', '$.chapter') }} as chapter,
        {{ mogov.json_str('payload', '$.chapter_name') }} as chapter_name,
        {{ mogov.json_str('payload', '$.title') }} as title_heading,
        source_url
    from {{ source('mo_revisor', 'chapters') }}
)

select
    chapter,
    chapter_name,
    {{ dbt.split_part('title_heading', "' '", 1) }} as title_numeral,
    {{ mogov.regex_replace_all('title_heading', '^[^ ]+ +', '') }} as title_name,
    source_url
from src
