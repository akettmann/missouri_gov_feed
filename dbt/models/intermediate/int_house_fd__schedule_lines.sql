-- House disclosure PDF text, each line tagged with the schedule it falls under (the nearest preceding
-- "Schedule X:" header in the same document). Column-header rows, "None disclosed." and boilerplate drop out.
with lines as (
    select
        {{ mogov.json_str('payload', '$.doc_id') }} as doc_id,
        {{ mogov.json_str('payload', '$.url') }} as document_url,
        {{ mogov.json_str('payload', '$.has_text') }} = 'true' as has_text,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.page'), dbt.type_int()) }} as page,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.line_no'), dbt.type_int()) }} as line_no,
        {{ mogov.json_str('payload', '$.text') }} as line_text
    from {{ source('raw', 'house_fd_pdf_lines') }}
),

sequenced as (
    select
        *,
        row_number() over (partition by doc_id order by page, line_no) as seq,
        case
            when
                lower(line_text) like 'schedule a:%' or lower(line_text) like 'schedule a and b%'
                then 'A: assets & unearned income'
            when lower(line_text) like 'schedule b:%' then 'B: transactions'
            when lower(line_text) like 'schedule c:%' then 'C: earned income'
            when lower(line_text) like 'schedule d:%' then 'D: liabilities'
            when lower(line_text) like 'schedule e:%' then 'E: positions'
            when lower(line_text) like 'schedule f:%' then 'F: agreements'
            when lower(line_text) like 'schedule g:%' then 'G: gifts'
            when lower(line_text) like 'schedule h:%' then 'H: travel'
            when lower(line_text) like 'schedule i:%' then 'I: charity in lieu of honoraria'
            when lower(line_text) like 'schedule j:%' then 'J: compensation over $5,000 from one source'
            when
                lower(line_text) like '%transaction date%' or lower(line_text) like 'id owner asset%'
                then 'PTR: transactions'
        end as header_schedule
    from lines
    where has_text
),

tagged as (
    select
        s.*,
        max(case when s.header_schedule is not null then s.seq end)
            over (partition by s.doc_id order by s.seq rows between unbounded preceding and current row) as header_seq
    from sequenced as s
)

select
    t.doc_id,
    t.document_url,
    t.page,
    t.line_no,
    t.seq,
    h.header_schedule as schedule,
    t.line_text,
    -- owner codes: SP spouse, DC dependent child, JT joint
    {{ mogov.regex_extract('t.line_text', '(?:^| )(SP|DC|JT)(?: |$)') }} as owner_code,
    {{ mogov.regex_extract('t.line_text', '(\\$[0-9,]+(?: - \\$[0-9,]+)?|Over \\$[0-9,]+|None)') }} as amount_range
from tagged as t
inner join tagged as h on t.doc_id = h.doc_id and t.header_seq = h.seq
where
    t.header_schedule is null
    and lower(t.line_text) not in ('none disclosed.', 'none disclosed')
    and lower(t.line_text) not like 'asset owner value%'
    and lower(t.line_text) not like 'type(s) $1,000?%'
    and lower(t.line_text) not like 'source type amount%'
    and lower(t.line_text) not like 'position name of organization%'
    and lower(t.line_text) not like '%for the complete list of asset type%'
    and lower(t.line_text) not like 'filing id #%'
