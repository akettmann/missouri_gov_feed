-- Official Manual biographies split per person. Legislative chapter entries start with
-- "District 12—FIRST LAST" and run until the next entry; lines are joined in reading order.
with lines as (
    select
        edition,
        chapter,
        page,
        line_no,
        line_text,
        source_url,
        row_number() over (partition by edition, chapter order by page, line_no) as seq,
        {{ mogov.regex_extract('line_text', '^District ([0-9]+) *[—–-] *[A-Z]') }} as entry_district,
        {{ mogov.regex_extract('line_text', '^District [0-9]+ *[—–-] *([A-Z][A-Z .,\'’-]+)$') }} as entry_name
    from {{ ref('stg_bluebook__lines') }}
    where chapter = 'legislative'
),

tagged as (
    select
        *,
        max(case when entry_district is not null then seq end)
            over (partition by edition, chapter order by seq rows between unbounded preceding and current row)
            as entry_seq,
        -- which roster section we're in: the running header names it
        max(case
            when line_text like '%STATE SENATORS%' then seq
        end) over (partition by edition order by seq rows between unbounded preceding and current row)
            as senate_header_seq,
        max(case
            when line_text like '%STATE REPRESENTATIVES%' then seq
        end) over (partition by edition order by seq rows between unbounded preceding and current row)
            as house_header_seq
    from lines
),

entries as (
    select
        t.edition,
        t.entry_seq,
        max(case when t.seq = t.entry_seq then t.entry_district end) as district,
        max(case when t.seq = t.entry_seq then t.entry_name end) as name_upper,
        max(case
            when t.seq = t.entry_seq then
                case
                    when coalesce(t.senate_header_seq, -1) > coalesce(t.house_header_seq, -1) then 'upper' else 'lower'
                end
        end) as chamber,
        max(t.source_url) as source_url,
        {{ dbt.listagg('t.line_text', "' '", 'order by t.seq') }} as bio_text
    from tagged as t
    where t.entry_seq is not null
    group by 1, 2
)

select
    edition,
    chamber,
    {{ dbt.safe_cast('district', dbt.type_int()) }} as district_number,
    name_upper,
    {{ mogov.name_key('name_upper') }} as name_key,
    bio_text,
    source_url
from entries
where name_upper is not null
