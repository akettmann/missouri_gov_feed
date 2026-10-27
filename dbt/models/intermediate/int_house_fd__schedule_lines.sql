-- House disclosure PDF text, each line tagged with the schedule it falls under (the nearest preceding
-- "Schedule X:" header in the same document). Column-header rows, "None disclosed." and boilerplate drop out.
-- PDFs from 2021 on extract their small-caps text with NUL characters; the words are restored first (#576).
with lines as (
    select
        doc_id,
        document_url,
        has_text,
        page,
        line_no,
        {{ mogov.house_fd_restore_text('line_text') }} as line_text
    from {{ ref('stg_house_fd__pdf_lines') }}
),

sequenced as (
    select
        *,
        row_number() over (partition by doc_id order by page, line_no) as seq,
        case
            when
                lower(line_text) like 'schedule a:%' or lower(line_text) like 'schedule a and b%'
                -- 2021+ layout: "Schedule A Asset Class Details" / "Schedule A Investment Vehicle Details"
                or lower(line_text) like 'schedule a %details'
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
            -- the form's closing pages (exclusion questions, certification, signature) follow the last schedule;
            -- their lines belong to no schedule (the sentinel is dropped below)
            when
                lower(line_text) like 'exclusions of spouse%' or lower(line_text) like 'certification and signature%'
                then 'end of form'
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
    {{ mogov.regex_extract('t.line_text', '(^| )(SP|DC|JT)( |$)', 2) }} as owner_code,
    {{ mogov.regex_extract('t.line_text', '(\\$[0-9,]+( - \\$[0-9,]+)?|Over \\$[0-9,]+|None)') }} as amount_range
from tagged as t
inner join tagged as h on t.doc_id = h.doc_id and t.header_seq = h.seq
where
    t.header_schedule is null
    and h.header_schedule != 'end of form'
    and lower(t.line_text) not in ('none disclosed.', 'none disclosed')
    and lower(t.line_text) not like 'asset owner value%'
    and lower(t.line_text) not like 'type(s) $1,000?%'
    and lower(t.line_text) not like 'source type amount%'
    and lower(t.line_text) not like 'position name of organization%'
    and lower(t.line_text) not like 'source (name and address)%'
    and lower(t.line_text) not like '%for the complete list of asset type%'
    and lower(t.line_text) not like 'filing id #%'
