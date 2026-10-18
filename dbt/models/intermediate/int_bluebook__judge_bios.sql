-- Official Manual judicial-chapter biographies split per judge. Circuit and associate circuit entries
-- are "<NAME IN CAPS>" followed by "Office address: ..."; appellate entries open with "<NAME IN CAPS> was
-- born / received / served ...". The bio runs until the next entry; words hyphenated across lines are rejoined.
with lines as (
    select
        edition,
        page,
        line_no,
        line_text,
        source_url,
        row_number() over (partition by edition order by page, line_no) as seq
    from {{ ref('stg_bluebook__lines') }}
    where chapter = 'judicial'
),

marked as (
    select
        *,
        coalesce(
            case
                when
                    lead(line_text) over (partition by edition order by seq) like 'Office address:%'
                    and {{ mogov.regex_matches('line_text', "^[A-Z][A-Z .,'’-]+$") }}
                    then line_text
            end,
            {{ mogov.regex_extract(
                'line_text',
                "^([A-Z][A-Z.'’-]+(?: [A-Z][A-Z.'’-]*)+) (?:was|is|has|received|graduated|served|earned|began|grew)"
            ) }}
        ) as entry_name
    from lines
),

tagged as (
    select
        *,
        max(case when entry_name is not null then seq end)
            over (partition by edition order by seq rows between unbounded preceding and current row) as entry_seq
    from marked
)

select
    edition,
    max(case when seq = entry_seq then entry_name end) as name_upper,
    {{ mogov.name_key("max(case when seq = entry_seq then entry_name end)") }} as name_key,
    {{ mogov.regex_replace_all(dbt.listagg('line_text', "' '", 'order by seq'), '([a-z])- ([a-z])', '\\1\\2') }}
        as bio_text,
    max(source_url) as source_url
from tagged
where entry_seq is not null
group by edition, entry_seq
